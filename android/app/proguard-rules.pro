# JNI 通过 GetMethodID 按字符串名字反射调用 NativeCallback 的方法。
# R8 无法静态感知这种反射调用，会混淆/移除方法名，导致 GetMethodID 抛
# NoSuchMethodError（pending exception），后续 JNI 调用再抛异常时 ART 直接 abort。
# 必须精确保留接口及其所有实现的方法名。
-keep interface ai.mnn.pocket.NativeCallback { *; }
-keep class ai.mnn.pocket.NativeCallback { *; }
-keep class ai.mnn.pocket.MnnLlmBridge$nativeCallback$1 { *; }
-keepclassmembers class * implements ai.mnn.pocket.NativeCallback {
    void onToken(java.lang.String);
    void onDone(java.lang.String);
    void onError(java.lang.String);
    void onStage(java.lang.String);
}
# @Keep 注解支持
-keep class androidx.annotation.Keep
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep <methods>;
}
