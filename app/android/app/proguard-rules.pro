# Conservative keep rules so a minified release still works. Prefer keeping
# what plugins need (Flutter JNI, Firebase reflection, Play services) over
# aggressive obfuscation that breaks MethodChannel / JNI lookups.

# Firebase (and Gson used by notifications) rely on generic signatures and
# runtime annotations. See https://firebase.google.com/docs/database/android/start
# ("Optional: Configure ProGuard") and flutter_local_notifications' Gson rules.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes SourceFile,LineNumberTable

# Flutter embedding / engine / JNI. The Gradle plugin also merges
# flutter_proguard_rules.pro (FlutterPlugin implementations); these extra
# keeps cover the JNI surface and GeneratedPluginRegistrant.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Firebase + Play services. SDKs ship consumer rules; keep the packages
# anyway so FCM, Google Sign-In, and ML Kit survive shrinking.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Sign-In 7.x talks to Credential Manager / Identity.
-keep class com.google.android.libraries.identity.** { *; }
-keep class androidx.credentials.** { *; }

# ML Kit text recognition (Latin). Keep the used API; dontwarn the unused
# script modules — google_mlkit_text_recognition's shared initializer
# references every script-specific recognizer (Chinese/Devanagari/Japanese/
# Korean), but we only depend on the Latin-script module. R8 in release
# mode hard-fails on those missing classes unless told they're optional.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# flutter_local_notifications (Gson payload models).
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-dontwarn sun.misc.**

# Sentry (DSN empty by default; JNI + stack traces). The plugin also ships
# consumer rules; keep the package so a later DSN still works.
-keep class io.sentry.** { *; }

# Drift / sqlite (encryption is sqlite3mc, not sqlcipher_flutter_libs).
-keep class androidx.sqlite.** { *; }
-keep class io.requery.android.database.** { *; }
-keep class net.sqlcipher.** { *; }
-dontwarn net.sqlcipher.**

# Flutter's embedding references Play Store deferred-component APIs
# (SplitCompat / SplitInstall) even when the app does not use dynamic
# feature modules. R8 hard-fails on those missing classes otherwise.
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
