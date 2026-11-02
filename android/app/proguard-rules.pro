# ML Kit text recognition references optional language-specific option classes
# (Chinese, Devanagari, Japanese, Korean) that are not bundled. Ignore them so
# R8 does not fail the release build.
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
