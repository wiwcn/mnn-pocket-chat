#include <jni.h>
#include <android/log.h>

#define MNN_POCKET_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "mnn_pocket_native", __VA_ARGS__)
#define MNN_POCKET_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "mnn_pocket_native", __VA_ARGS__)

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <functional>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <unistd.h>
#include <vector>
#include <csignal>
#include <ctime>
#include <dlfcn.h>
#include <exception>
#include <unwind.h>

#include "llm/llm.hpp"

using MNN::Transformer::ChatMessage;
using MNN::Transformer::ChatMessages;
using MNN::Transformer::Llm;
using MNN::Transformer::LlmContext;
using MNN::Transformer::LlmStatus;

namespace {

JavaVM* g_vm = nullptr;

// ---------------------------------------------------------------------------
// 同步落盘的 native trace。
//
// 背景：此前 stage 打点走 __android_log_print（只进 logcat），而用户能导出的
// 是应用内 debug.log，导致 native 崩溃现场完全不可见。这里改为：
//   1) 所有关键阶段同步 open/write/close + fsync 到一个独立文件，即使随后
//      SIGSEGV，磁盘上也保留“崩溃前最后一步”；
//   2) 注册 SIGSEGV/SIGABRT/SIGBUS/SIGILL 处理器，崩溃瞬间用 backtrace 写出
//       native 堆栈，从而一次性拿到根因，不再靠猜。
//
// 信号处理器中只调用 async-signal-safe 的操作（open/write/fsync/close 和
// backtrace_symbols_fd 的底层 write），不使用 malloc/iostream/std::string。
// ---------------------------------------------------------------------------
std::string g_nativeTracePath;
std::atomic<int> g_crashHandled{0};

// async-signal-safe：不用 std::string，传入已格式化的 C 字符串。
static void traceWriteRaw(const char* line) {
    if (g_nativeTracePath.empty()) return;
    int fd = ::open(g_nativeTracePath.c_str(),
                    O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return;
    size_t len = ::strlen(line);
    ssize_t ignored = ::write(fd, line, len);
    (void)ignored;
    ::fsync(fd);
    ::close(fd);
}

// 普通打点：时间戳 + 文本，同步落盘。非信号上下文可用 std::string 拼接。
static void traceStage(const char* stage) {
    if (g_nativeTracePath.empty()) return;
    timespec ts{};
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tmVal{};
    localtime_r(&ts.tv_sec, &tmVal);
    char buf[512];
    int n = snprintf(buf, sizeof(buf),
                     "%02d-%02d %02d:%02d:%02d.%03d N/native: %s\n",
                     tmVal.tm_mon + 1, tmVal.tm_mday,
                     tmVal.tm_hour, tmVal.tm_min, tmVal.tm_sec,
                     (int)(ts.tv_nsec / 1000000), stage);
    if (n > 0) traceWriteRaw(buf);
    MNN_POCKET_LOGI("stage: %s", stage);
}

// 用 libunwind（NDK 稳定支持）采集返回地址，写入 trace 文件。
struct UnwindContext {
    int fd;
    int index;
};

static _Unwind_Reason_Code unwindCallback(struct _Unwind_Context* ctx, void* arg) {
    auto* uc = static_cast<UnwindContext*>(arg);
    if (uc->index >= 64) return _URC_END_OF_STACK;
    uintptr_t ip = _Unwind_GetIP(ctx);
    char line[512];
    int n = 0;
    Dl_info info{};
    if (dladdr(reinterpret_cast<void*>(ip), &info) != 0 &&
        info.dli_fname != nullptr) {
        // so 名 + 模块内偏移，配合带符号 so 可直接 addr2line。
        const char* base = info.dli_fname;
        const char* slash = strrchr(base, '/');
        if (slash != nullptr) base = slash + 1;
        uintptr_t offset = ip - reinterpret_cast<uintptr_t>(info.dli_fbase);
        if (info.dli_sname != nullptr) {
            uintptr_t symoff = ip - reinterpret_cast<uintptr_t>(info.dli_saddr);
            n = snprintf(line, sizeof(line),
                         "  #%02d pc 0x%lx  %s+0x%lx  (%s+0x%lx)\n",
                         uc->index, (unsigned long)ip, base,
                         (unsigned long)offset, info.dli_sname,
                         (unsigned long)symoff);
        } else {
            n = snprintf(line, sizeof(line), "  #%02d pc 0x%lx  %s+0x%lx\n",
                         uc->index, (unsigned long)ip, base,
                         (unsigned long)offset);
        }
    } else {
        n = snprintf(line, sizeof(line), "  #%02d pc 0x%lx\n",
                     uc->index, (unsigned long)ip);
    }
    if (n > 0 && uc->fd >= 0) {
        ssize_t ignored = ::write(uc->fd, line, (size_t)n);
        (void)ignored;
    }
    ++uc->index;
    return _URC_NO_REASON;
}

// 崩溃信号处理器：写出信号编号 + native 返回地址，然后恢复默认处理让进程正常终止。
static void crashSignalHandler(int sig) {
    // 只允许第一个信号进入，避免多重信号递归。
    if (g_crashHandled.exchange(1) != 0) {
        _exit(128 + sig);
    }
    char head[160];
    int n = snprintf(head, sizeof(head),
                     "\n===== NATIVE CRASH =====\nsignal=%d (%s)\n"
                     "backtrace (relative to libmnnllm_jni.so / libc, "
                     "use addr2line with unstripped so):\n",
                     sig, sig == SIGSEGV ? "SIGSEGV" :
                          sig == SIGABRT ? "SIGABRT" :
                          sig == SIGBUS  ? "SIGBUS"  : "SIGILL/FPE");
    traceWriteRaw(head);

    int fd = g_nativeTracePath.empty()
                 ? -1
                 : ::open(g_nativeTracePath.c_str(),
                          O_WRONLY | O_CREAT | O_APPEND, 0666);
    UnwindContext uc{fd, 0};
    _Unwind_Backtrace(unwindCallback, &uc);
    if (fd >= 0) {
        ::fsync(fd);
        ::close(fd);
    }
    traceWriteRaw("===== END CRASH =====\n");

    // 恢复默认动作并重新触发，保证系统 tombstone 正常生成。
    signal(sig, SIG_DFL);
    raise(sig);
    _exit(128 + sig);
}

// 未捕获的 C++ 异常会走 std::terminate → abort()，产生 SIGABRT。
// 捕获它并打印异常类型/what，可直接定位本次崩溃根因。
static void nativeTerminateHandler() {
    char head[80];
    int n = snprintf(head, sizeof(head), "\n===== C++ TERMINATE (uncaught exception) =====\n");
    if (n > 0) traceWriteRaw(head);
    try {
        std::exception_ptr ep = std::current_exception();
        if (ep) {
            try {
                std::rethrow_exception(ep);
            } catch (const std::exception& e) {
                char buf[512];
                int m = snprintf(buf, sizeof(buf), "what(): %s\n", e.what());
                if (m > 0) traceWriteRaw(buf);
            } catch (...) {
                traceWriteRaw("unknown exception (non-std)\n");
            }
        } else {
            traceWriteRaw("terminate without current exception\n");
        }
    } catch (...) {
        traceWriteRaw("failed to extract exception\n");
    }
    // 同样采集堆栈。
    int fd = g_nativeTracePath.empty() ? -1 : ::open(
        g_nativeTracePath.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0666);
    UnwindContext uc{fd, 0};
    _Unwind_Backtrace(unwindCallback, &uc);
    if (fd >= 0) {
        ::fsync(fd);
        ::close(fd);
    }
    traceWriteRaw("===== END TERMINATE =====\n");
    // 正常终止进程（abort 会再次触发 SIGABRT handler，但 g_crashHandled 已有保护）。
    std::abort();
}

static void installCrashHandlers() {
    std::set_terminate(nativeTerminateHandler);
    signal(SIGSEGV, crashSignalHandler);
    signal(SIGABRT, crashSignalHandler);
    signal(SIGBUS, crashSignalHandler);
    signal(SIGILL, crashSignalHandler);
    signal(SIGFPE, crashSignalHandler);
}

std::string jstringToUtf8(JNIEnv* env, jstring js) {
    if (js == nullptr) {
        return {};
    }
    const jsize len = env->GetStringLength(js);
    const jchar* chars = env->GetStringChars(js, nullptr);
    std::string out;
    out.reserve(static_cast<size_t>(len) * 3);
    for (jsize i = 0; i < len; ++i) {
        uint32_t cp = chars[i];
        if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < len) {
            const uint32_t low = chars[i + 1];
            if (low >= 0xDC00 && low <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                ++i;
            }
        }
        if (cp < 0x80) {
            out.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
    env->ReleaseStringChars(js, chars);
    return out;
}

jstring utf8ToJstring(JNIEnv* env, const std::string& text) {
    std::u16string out;
    out.reserve(text.size());
    size_t i = 0;
    while (i < text.size()) {
        const unsigned char c = static_cast<unsigned char>(text[i]);
        uint32_t cp = 0xFFFD;
        size_t step = 1;
        if (c < 0x80) {
            cp = c;
        } else if ((c & 0xE0) == 0xC0 && i + 1 < text.size()) {
            cp = ((c & 0x1F) << 6) |
                 (static_cast<unsigned char>(text[i + 1]) & 0x3F);
            step = 2;
        } else if ((c & 0xF0) == 0xE0 && i + 2 < text.size()) {
            cp = ((c & 0x0F) << 12) |
                 ((static_cast<unsigned char>(text[i + 1]) & 0x3F) << 6) |
                 (static_cast<unsigned char>(text[i + 2]) & 0x3F);
            step = 3;
        } else if ((c & 0xF8) == 0xF0 && i + 3 < text.size()) {
            cp = ((c & 0x07) << 18) |
                 ((static_cast<unsigned char>(text[i + 1]) & 0x3F) << 12) |
                 ((static_cast<unsigned char>(text[i + 2]) & 0x3F) << 6) |
                 (static_cast<unsigned char>(text[i + 3]) & 0x3F);
            step = 4;
        }
        i += step;
        if (cp <= 0xFFFF) {
            out.push_back(static_cast<char16_t>(cp));
        } else {
            cp -= 0x10000;
            out.push_back(static_cast<char16_t>(0xD800 + (cp >> 10)));
            out.push_back(static_cast<char16_t>(0xDC00 + (cp & 0x3FF)));
        }
    }
    return env->NewString(reinterpret_cast<const jchar*>(out.data()),
                          static_cast<jsize>(out.size()));
}

struct JavaCallback {
    jobject object = nullptr;
    jmethodID onToken = nullptr;
    jmethodID onDone = nullptr;
    jmethodID onError = nullptr;
    jmethodID onStage = nullptr;
    bool valid = false;

    JNIEnv* env(bool& attached) {
        attached = false;
        if (g_vm == nullptr) {
            return nullptr;
        }
        JNIEnv* e = nullptr;
        const jint ret =
            g_vm->GetEnv(reinterpret_cast<void**>(&e), JNI_VERSION_1_6);
        if (ret == JNI_EDETACHED) {
            if (g_vm->AttachCurrentThread(&e, nullptr) != JNI_OK) {
                return nullptr;
            }
            attached = true;
        }
        return e;
    }

    void emitToken(const std::string& text) {
        if (!valid || text.empty()) return;
        bool attached = false;
        JNIEnv* e = env(attached);
        if (e == nullptr) return;
        jstring value = utf8ToJstring(e, text);
        e->CallVoidMethod(object, onToken, value);
        e->DeleteLocalRef(value);
        if (e->ExceptionCheck()) e->ExceptionClear();
        if (attached) g_vm->DetachCurrentThread();
    }

    void emitDone(const std::string& stats) {
        if (!valid) return;
        bool attached = false;
        JNIEnv* e = env(attached);
        if (e == nullptr) return;
        jstring value = utf8ToJstring(e, stats);
        e->CallVoidMethod(object, onDone, value);
        e->DeleteLocalRef(value);
        if (e->ExceptionCheck()) e->ExceptionClear();
        if (attached) g_vm->DetachCurrentThread();
    }

    void emitError(const std::string& message) {
        if (!valid) return;
        bool attached = false;
        JNIEnv* e = env(attached);
        if (e == nullptr) return;
        jstring value = utf8ToJstring(e, message);
        e->CallVoidMethod(object, onError, value);
        e->DeleteLocalRef(value);
        if (e->ExceptionCheck()) e->ExceptionClear();
        if (attached) g_vm->DetachCurrentThread();
    }

    // 阶段打点：同步落盘到 native trace（崩溃时仍保留），同时经 Java 回调
    // 转发到 Dart 的 debug.log（异步，可能来不及落盘，仅作辅助）。
    void emitStage(const std::string& stage) {
        traceStage(stage.c_str());
        if (onStage == nullptr) return;
        bool attached = false;
        JNIEnv* e = env(attached);
        if (e == nullptr) return;
        jstring value = utf8ToJstring(e, stage);
        e->CallVoidMethod(object, onStage, value);
        e->DeleteLocalRef(value);
        if (e->ExceptionCheck()) e->ExceptionClear();
        if (attached) g_vm->DetachCurrentThread();
    }

    bool bind(JNIEnv* env, jobject callbackObject) {
        // 必须用全局引用：MNN 的流式 token 回调可能来自内部线程，局部引用
        // 跨线程使用是未定义行为，官方 MNN Chat 同样使用 NewGlobalRef。
        object = env->NewGlobalRef(callbackObject);
        jclass cls = env->GetObjectClass(callbackObject);
        if (cls == nullptr) return false;
        onToken = env->GetMethodID(cls, "onToken", "(Ljava/lang/String;)V");
        onDone = env->GetMethodID(cls, "onDone", "(Ljava/lang/String;)V");
        onError = env->GetMethodID(cls, "onError", "(Ljava/lang/String;)V");
        onStage = env->GetMethodID(cls, "onStage", "(Ljava/lang/String;)V");
        env->DeleteLocalRef(cls);
        valid = onToken != nullptr && onDone != nullptr && onError != nullptr;
        if (env->ExceptionCheck()) env->ExceptionClear();
        return valid;
    }

    void release(JNIEnv* env) {
        if (object != nullptr) {
            env->DeleteGlobalRef(object);
            object = nullptr;
        }
        valid = false;
    }
};

struct Session {
    Llm* llm = nullptr;
    std::atomic<bool> stop{false};
};

void restoreRunning(Llm* llm) {
    auto* context = llm == nullptr ? nullptr : llm->getContext();
    if (context != nullptr &&
        (context->status == LlmStatus::MAX_TOKENS_FINISHED ||
         context->status == LlmStatus::NORMAL_FINISHED)) {
        const_cast<LlmContext*>(context)->status = LlmStatus::RUNNING;
    }
}

class Utf8Processor {
public:
    explicit Utf8Processor(std::function<void(const std::string&)> callback)
        : callback_(std::move(callback)) {}

    void feed(const char* data, size_t len) {
        buffer_.append(data, len);
        size_t i = 0;
        std::string complete;
        while (i < buffer_.size()) {
            const int length =
                charLength(static_cast<unsigned char>(buffer_[i]));
            if (length == 0 || i + static_cast<size_t>(length) > buffer_.size()) {
                break;
            }
            complete.append(buffer_, i, static_cast<size_t>(length));
            i += static_cast<size_t>(length);
        }
        buffer_.erase(0, i);
        if (!complete.empty()) callback_(complete);
    }

    void flush() {
        if (!buffer_.empty()) {
            callback_(buffer_);
            buffer_.clear();
        }
    }

private:
    static int charLength(unsigned char byte) {
        if ((byte & 0x80) == 0) return 1;
        if ((byte & 0xE0) == 0xC0) return 2;
        if ((byte & 0xF0) == 0xE0) return 3;
        if ((byte & 0xF8) == 0xF0) return 4;
        return 0;
    }

    std::string buffer_;
    std::function<void(const std::string&)> callback_;
};

class LlmStreamBuffer : public std::streambuf {
public:
    using Callback = std::function<void(const char*, size_t)>;
    explicit LlmStreamBuffer(Callback callback) : callback_(std::move(callback)) {}

protected:
    std::streamsize xsputn(const char* s, std::streamsize n) override {
        if (callback_) callback_(s, static_cast<size_t>(n));
        return n;
    }

private:
    Callback callback_;
};

struct StreamState {
    std::stringstream buffer;
    std::string pending;
    bool pendingEop = false;
    bool finished = false;
    std::function<void(const std::string&)> onToken;

    void emit(const std::string& text) {
        if (text.empty()) return;
        buffer << text;
        if (onToken) onToken(text);
    }

    void feed(const std::string& chunk) {
        pending += chunk;
        const std::string marker = "<eop>";
        const size_t pos = pending.find(marker);
        if (pos != std::string::npos) {
            emit(pending.substr(0, pos));
            pending.clear();
            pendingEop = true;
            return;
        }
        size_t keep = 0;
        const size_t maxKeep = std::min<size_t>(marker.size() - 1, pending.size());
        for (size_t n = maxKeep; n > 0; --n) {
            if (marker.compare(0, n, pending.substr(pending.size() - n)) == 0) {
                keep = n;
                break;
            }
        }
        emit(pending.substr(0, pending.size() - keep));
        pending.erase(0, pending.size() - keep);
    }

    void flushPending() {
        if (!pending.empty()) emit(pending);
        pending.clear();
    }
};

void resolveStepping(Llm* llm, StreamState& state, int currentSize,
                     int maxNewTokens, bool stopRequested,
                     bool& textEnd) {
    const auto* context = llm == nullptr ? nullptr : llm->getContext();
    if (context != nullptr && context->status == LlmStatus::MAX_TOKENS_FINISHED &&
        !stopRequested && currentSize < maxNewTokens) {
        restoreRunning(llm);
        if (state.pendingEop) {
            textEnd = false;
            state.pendingEop = false;
        }
        return;
    }
    if (context != nullptr && context->status == LlmStatus::NORMAL_FINISHED &&
        !state.pendingEop && !stopRequested && currentSize < maxNewTokens) {
        restoreRunning(llm);
        return;
    }
    if (state.pendingEop) {
        state.pendingEop = false;
        textEnd = true;
    }
}

std::string buildStats(const LlmContext* context) {
    const double prefillSeconds =
        context == nullptr ? 0 : context->prefill_us / 1e6;
    const double decodeSeconds =
        context == nullptr ? 0 : context->decode_us / 1e6;
    const double prefillTps =
        prefillSeconds > 0 ? context->prompt_len / prefillSeconds : 0;
    const double decodeTps =
        decodeSeconds > 0 ? context->gen_seq_len / decodeSeconds : 0;
    const long long elapsedMs =
        context == nullptr ? 0 : (context->prefill_us + context->decode_us) / 1000;
    char buffer[256];
    std::snprintf(
        buffer, sizeof(buffer),
        "{\"prefillTps\":%.2f,\"decodeTps\":%.2f,\"promptTokens\":%d,"
        "\"outputTokens\":%d,\"elapsedMs\":%lld}",
        prefillTps, decodeTps, context == nullptr ? 0 : context->prompt_len,
        context == nullptr ? 0 : context->gen_seq_len, elapsedMs);
    return std::string(buffer);
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    installCrashHandlers();
    traceStage("JNI_OnLoad: crash handlers installed");
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT void JNICALL
Java_ai_mnn_pocket_MnnLlmBridge_nativeSetLogPath(JNIEnv* env, jobject,
                                                  jstring path) {
    if (path == nullptr) return;
    g_nativeTracePath = jstringToUtf8(env, path);
    traceStage("nativeSetLogPath: trace path configured");
}

extern "C" JNIEXPORT jlong JNICALL
Java_ai_mnn_pocket_MnnLlmBridge_nativeCreate(JNIEnv* env, jobject /*thiz*/,
                                             jstring configPath,
                                             jstring overrides) {
    const std::string path = jstringToUtf8(env, configPath);
    const std::string config = jstringToUtf8(env, overrides);
    traceStage("nativeCreate: begin");
    traceStage((std::string("nativeCreate: config=") + config).c_str());
    try {
        Llm* llm = Llm::createLLM(path);
        if (llm == nullptr) {
            traceStage("nativeCreate: createLLM returned null");
            return 0;
        }
        if (!config.empty()) {
            llm->set_config(config);
        }
        traceStage("nativeCreate: load begin");
        if (!llm->load()) {
            traceStage("nativeCreate: load FAILED");
            delete llm;
            return 0;
        }
        traceStage("nativeCreate: load OK");
        auto* session = new Session();
        session->llm = llm;
        return reinterpret_cast<jlong>(session);
    } catch (const std::exception& e) {
        traceStage((std::string("nativeCreate: exception ") + e.what()).c_str());
        return 0;
    } catch (...) {
        traceStage("nativeCreate: unknown exception");
        return 0;
    }
}

extern "C" JNIEXPORT void JNICALL
Java_ai_mnn_pocket_MnnLlmBridge_nativeGenerate(
    JNIEnv* env, jobject /*thiz*/, jlong handle, jobjectArray roles,
    jobjectArray contents, jint maxTokens, jobject callbackObject) {
    traceStage("nativeGenerate: CALLED (entry)");
    auto* session = reinterpret_cast<Session*>(handle);
    if (session == nullptr || session->llm == nullptr) {
        traceStage("nativeGenerate: null session -> return");
        return;
    }
    traceStage("nativeGenerate: session OK");

    // 全局引用绑定：对齐官方 MNN Chat 的做法。
    JavaCallback callback;
    if (!callback.bind(env, callbackObject)) {
        traceStage("nativeGenerate: bind callback FAILED -> return");
        MNN_POCKET_LOGE("nativeGenerate: failed to bind callback");
        return;
    }
    traceStage("nativeGenerate: callback bound");

    ChatMessages history;
    const jsize count = env->GetArrayLength(roles);
    history.reserve(static_cast<size_t>(count));
    for (jsize i = 0; i < count; ++i) {
        auto role = static_cast<jstring>(env->GetObjectArrayElement(roles, i));
        auto content =
            static_cast<jstring>(env->GetObjectArrayElement(contents, i));
        history.emplace_back(jstringToUtf8(env, role),
                             jstringToUtf8(env, content));
        env->DeleteLocalRef(role);
        env->DeleteLocalRef(content);
    }

    session->stop.store(false);
    StreamState state;
    // 将 token 出口绑定到 Java 回调。
    state.onToken = [&callback](const std::string& text) {
        callback.emitToken(text);
    };
    Utf8Processor processor(
        [&state](const std::string& chunk) { state.feed(chunk); });
    LlmStreamBuffer streamBuffer(
        [&processor](const char* data, size_t len) {
            processor.feed(data, len);
        });
    std::ostream output(&streamBuffer);

    callback.emitStage("native: enter generate, history=" +
                       std::to_string(count));
    try {
        restoreRunning(session->llm);
        callback.emitStage("native: prefill response begin");
        session->llm->response(history, &output, "<eop>", 0);
        callback.emitStage("native: prefill response done");
        int currentSize = 0;
        bool textEnd = false;
        const int limit = maxTokens > 0 ? maxTokens : 512;
        resolveStepping(session->llm, state, currentSize, limit,
                        session->stop.load(), textEnd);
        while (!session->stop.load() && !textEnd && currentSize < limit) {
            session->llm->generate(1);
            ++currentSize;
            if (currentSize <= 2 || currentSize % 32 == 0) {
                callback.emitStage("native: decoded " +
                                   std::to_string(currentSize) + " tokens");
            }
            resolveStepping(session->llm, state, currentSize, limit,
                            session->stop.load(), textEnd);
        }
        processor.flush();
        state.flushPending();
        callback.emitStage("native: decode loop done, tokens=" +
                           std::to_string(currentSize));

        const std::string assistant = state.buffer.str();
        if (!assistant.empty()) {
            history.emplace_back("assistant", assistant);
            callback.emitStage("native: syncPromptCache begin");
            session->llm->syncPromptCache(history);
        }
        callback.emitStage("native: emitDone");
        callback.emitDone(buildStats(session->llm->getContext()));
    } catch (const std::exception& e) {
        MNN_POCKET_LOGE("nativeGenerate exception: %s", e.what());
        callback.emitStage(std::string("native: exception ") + e.what());
        callback.emitError(e.what());
    } catch (...) {
        MNN_POCKET_LOGE("nativeGenerate unknown exception");
        callback.emitStage("native: unknown exception");
        callback.emitError("native generation failed");
    }
    // 释放全局引用；必须在所有 emit 之后再删，避免回调 use-after-free。
    callback.release(env);
}

extern "C" JNIEXPORT void JNICALL
Java_ai_mnn_pocket_MnnLlmBridge_nativeStop(JNIEnv*, jobject, jlong handle) {
    auto* session = reinterpret_cast<Session*>(handle);
    if (session != nullptr) {
        session->stop.store(true);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_ai_mnn_pocket_MnnLlmBridge_nativeReset(JNIEnv*, jobject, jlong handle) {
    auto* session = reinterpret_cast<Session*>(handle);
    if (session != nullptr && session->llm != nullptr) {
        session->llm->reset();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_ai_mnn_pocket_MnnLlmBridge_nativeRelease(JNIEnv*, jobject, jlong handle) {
    auto* session = reinterpret_cast<Session*>(handle);
    if (session == nullptr) return;
    if (session->llm != nullptr) {
        delete session->llm;
        session->llm = nullptr;
    }
    delete session;
}
