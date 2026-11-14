# ---------------------------------------------------------------------------
# 应用级 R8 / ProGuard 规则
# ---------------------------------------------------------------------------
# Flutter 引擎（io.flutter:*-release AAR）自带 consumer-rules.pro，会保留
# FlutterJNI / 平台通道所需的全部反射入口，无需在此重复声明。
# GeneratedPluginRegistrant 是编译期生成的 Kotlin 代码，对插件的引用是静态
# 的，因此 Flutter 插件也不需要额外的 keep 规则。

# 保留行号，便于崩溃栈定位（R8 会做内联/裁剪，没有行号栈会很难读）。
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# OkHttp / java.beans 在 Android 上不存在，R8 探测时的无害告警。
-dontwarn java.beans.**
-dontwarn org.slf4j.**
