package ai.mnn.pocket

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/** Thin Kotlin facade over the MNN libllm JNI bridge. */
class MnnLlmBridge(messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, "mnn_pocket/engine")
    private val eventChannel = EventChannel(messenger, "mnn_pocket/events")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)

    @Volatile
    private var handle: Long = 0L

    @Volatile
    private var sink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
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
                Thread({
                    var created = 0L
                    try {
                        if (handle != 0L) {
                            nativeRelease(handle)
                            handle = 0L
                        }
                        created = nativeCreate(path, overrides)
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("load_failed", t.message ?: "load failed", null)
                        }
                        return@Thread
                    }
                    handle = created
                    mainHandler.post { result.success(created != 0L) }
                }, "mnn-load").start()
            }

            "generate" -> {
                val roles = call.argument<List<String>>("roles")
                val contents = call.argument<List<String>>("contents")
                val maxTokens = call.argument<Int>("maxTokens") ?: 512
                if (handle == 0L) {
                    result.error("not_loaded", "Model is not loaded", null)
                    return
                }
                if (roles == null || contents == null || roles.size != contents.size) {
                    result.error("bad_args", "roles/contents mismatch", null)
                    return
                }
                if (!busy.compareAndSet(false, true)) {
                    result.error("busy", "Generation already running", null)
                    return
                }
                val current = handle
                Thread({
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
                }, "mnn-generate").start()
                result.success(null)
            }

            "stop" -> {
                if (handle != 0L) nativeStop(handle)
                result.success(null)
            }

            "reset" -> {
                if (handle != 0L) nativeReset(handle)
                result.success(null)
            }

            "release" -> {
                if (handle != 0L) {
                    nativeRelease(handle)
                    handle = 0L
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private val nativeCallback = object : NativeCallback {
        override fun onToken(text: String) {
            emit(mapOf("type" to "token", "text" to text))
        }

        override fun onDone(statsJson: String) {
            emit(mapOf("type" to "done", "stats" to statsJson))
        }

        override fun onError(message: String) {
            emit(mapOf("type" to "error", "message" to message))
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

interface NativeCallback {
    fun onToken(text: String)
    fun onDone(statsJson: String)
    fun onError(message: String)
}
