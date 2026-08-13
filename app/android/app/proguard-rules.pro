# google_mlkit_text_recognition's shared TextRecognizer.initialize() code
# references every script-specific recognizer (Chinese/Devanagari/Japanese/
# Korean), but we only depend on the Latin-script module. R8 in release
# mode hard-fails on those missing classes unless told they're optional.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
