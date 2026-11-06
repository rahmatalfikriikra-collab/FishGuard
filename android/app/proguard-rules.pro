# R8 rules for FishGuard.
#
# The app reads the KKP DPI table with ML Kit's *Latin* text recogniser only
# (see lib/services/ocr_mobile.dart). google_mlkit_text_recognition still
# references the Chinese, Devanagari, Japanese and Korean option classes, but
# those recogniser libraries are deliberately not bundled — the base model adds
# tens of MB per script and the table is printed in Latin script.
#
# R8 treats the missing references as an error, so they are declared as
# optional here: present at runtime if ever added, harmless if not.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit resolves its scanners reflectively.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text** { *; }

# The plugin talks to Dart over the platform channel by name.
-keep class com.google_mlkit_text_recognition.** { *; }
