package ai.mnn.pocket

import android.os.Handler
import android.os.Looper
import androidx.annotation.Keep
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Thin Kotlin facade over the MNN libllm JNI bridge. */
class MnnLlmBridge(messenger: BinaryMessenger, logDir: String? = null) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, "mnn_pocket/engine")
    private val eventChannel = EventChannel(messenger, "mnn_pocket/events")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)

    /**
     * 所有触碰底层 Llm 的重型操作（load / generate / release / reset）都在
     * 同一个单线程执行器上串行执行。生成可能持续数十秒；此前 release/load
     * 可在生成进行中从另一线程 delete 正在使用的 Session，造成
     * use-after-free（SIGSEGV 闪退）。串行化后，release/load 会排队等到
     * 当前 generate 结束再执行，从根本上消除竞态。
     */
    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "mnn-engine-worker") }

    /**
     * 保护 [handle] 的读-改-写与 stop 的即时调用互斥：release/load 在释放前
     * 先把 handle 归零并持有该锁；stop 读 handle 与 nativeStop 也在锁内，
     * 因此永远不会对一个正在/已经 delete 的 Session 调用 nativeStop。
     */
    private val handleLock = Any()

    @Volatile
    private var handle: Long = 0L

    @Volatile
    private var sink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        // 把 native trace 路径注入到 JNI：native 崩溃时同步落盘堆栈到该文件。
        if (!logDir.isNullOrEmpty()) {
            try {
                val tracePath = java.io.File(logDir, "native_trace.log").absolutePath
                nativeSetLogPath(tracePath)
            } catch (_: Throwable) {
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> {
                val path = call.argument<String>("configPath")
                val overrides = call.argument<String>("overrides") ?: "{}"
                if (path == null) {
                    result.error("bad_args", "configPath is required", null)
                    return
                }
                worker.execute {
                    var created = 0L
                    try {
                        // 与 stop 互斥地取出旧句柄并归零，随后再释放。
                        val old = synchronized(handleLock) {
                            val value = handle
                            handle = 0L
                            value
                        }
                        if (old != 0L) nativeRelease(old)
                        created = nativeCreate(path, overrides)
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("load_failed", t.message ?: "load failed", null)
                        }
                        return@execute
                    }
                    synchronized(handleLock) { handle = created }
                    mainHandler.post { result.success(created != 0L) }
                }
            }

            "generate" -> {
                val roles = call.argument<List<String>>("roles")
                val contents = call.argument<List<String>>("contents")
                val maxTokens = call.argument<Int>("maxTokens") ?: 512
                if (roles == null || contents == null || roles.size != contents.size) {
                    result.error("bad_args", "roles/contents mismatch", null)
                    return
                }
                if (!busy.compareAndSet(false, true)) {
                    result.error("busy", "Generation already running", null)
                    return
                }
                // 生成方法立即返回，token/done/error 通过 EventChannel 推送。
                result.success(null)
                worker.execute {
                    // 句柄读取放在串行队列内，保证不会与 load/release 并发改写。
                    val current = synchronized(handleLock) { handle }
                    if (current == 0L) {
                        busy.set(false)
                        emit(mapOf("type" to "error", "message" to "Model is not loaded"))
                        return@execute
                    }
                    try {
                        nativeGenerate(
                            current,
                            roles.toTypedArray(),
                            contents.toTypedArray(),
                            maxTokens,
                            nativeCallback,
                        )
                    } catch (t: Throwable) {
                        emit(mapOf("type" to "error", "message" to (t.message ?: "native error")))
                    } finally {
                        busy.set(false)
                    }
                }
            }

            "stop" -> {
                // stop 只设置 native 侧的原子标志、不释放对象，必须即时调用
                // （若排进 worker 会落在生成之后而失去意义）。用 handleLock
                // 保证不会对一个正在/已经 delete 的 Session 调用 nativeStop。
                synchronized(handleLock) {
                    val current = handle
                    if (current != 0L) {
                        try {
                            nativeStop(current)
                        } catch (_: Throwable) {
                        }
                    }
                }
                result.success(null)
            }

            "reset" -> {
                worker.execute {
                    val current = synchronized(handleLock) { handle }
                    if (current != 0L) {
                        try {
                            nativeReset(current)
                        } catch (_: Throwable) {
                        }
                    }
                    mainHandler.post { result.success(null) }
                }
            }

            "release" -> {
                worker.execute {
                    // 持有 handleLock 归零，之后才 delete；stop 拿不到旧句柄。
                    val current = synchronized(handleLock) {
                        val value = handle
                        handle = 0L
                        value
                    }
                    if (current != 0L) {
                        try {
                            nativeRelease(current)
                        } catch (_: Throwable) {
                        }
                    }
                    mainHandler.post { result.success(null) }
                }
            }

            else -> result.notImplemented()
        }
    }

    // JNI 通过 GetMethodID 按名字反射调用这些方法；必须用 @Keep 防止 R8
    // 在 release 构建中混淆方法名，否则 GetMethodID 失败抛 NoSuchMethodError
    // 并触发 pending exception 连锁 abort。
    @Keep
    private val nativeCallback = object : NativeCallback {
        @Keep
        override fun onToken(text: String) {
            emit(mapOf("type" to "token", "text" to text))
        }

        @Keep
        override fun onDone(statsJson: String) {
            emit(mapOf("type" to "done", "stats" to statsJson))
        }

        @Keep
        override fun onError(message: String) {
            emit(mapOf("type" to "error", "message" to message))
        }

        @Keep
        override fun onStage(stage: String) {
            emit(mapOf("type" to "stage", "message" to stage))
        }
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { sink?.success(event) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private external fun nativeSetLogPath(path: String)

    private external fun nativeCreate(configPath: String, overridesJson: String): Long
    private external fun nativeGenerate(
        handle: Long,
        roles: Array<String>,
        contents: Array<String>,
        maxTokens: Int,
        callback: NativeCallback,
    )

    private external fun nativeStop(handle: Long)
    private external fun nativeReset(handle: Long)
    private external fun nativeRelease(handle: Long)

    companion object {
        init {
            System.loadLibrary("mnnllm_jni")
        }
    }
}

@Keep
interface NativeCallback {
    @Keep
    fun onToken(text: String)
    @Keep
    fun onDone(statsJson: String)
    @Keep
    fun onError(message: String)
    @Keep
    fun onStage(stage: String)
}
