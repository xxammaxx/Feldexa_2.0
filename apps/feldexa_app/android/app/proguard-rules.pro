# T003 release R8 rules.
#
# google_mlkit_text_recognition 1.0.2 declares the non-Latin ML Kit script
# recognizers as compileOnly dependencies; only the default Latin recognizer
# (com.google.mlkit:text-recognition:16.0.1) is an implementation dependency.
# The plugin's Android code switches on a script index, so R8 sees references to
# the optional Chinese/Devanagari/Japanese/Korean option classes even though
# Feldexa only ever creates the Latin recognizer.
#
# These exact rules are the ones AGP generated in
# build/app/outputs/mapping/release/missing_rules.txt. They suppress only the
# warnings for those absent optional classes; they do not add languages, keep
# unused recognizers, or change network behaviour. If a non-Latin script is ever
# required, add the corresponding com.google.mlkit:text-recognition-<script>
# implementation dependency instead of relying on these rules.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
