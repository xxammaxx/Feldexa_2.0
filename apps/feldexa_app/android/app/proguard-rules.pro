# T003 release R8 rules — emptied by T321B (2026-11-24).
#
# The `-dontwarn` rules for the optional non-Latin ML Kit script recognizers
# (chinese/devanagari/japanese/korean) came from the unused Dart wrapper
# `google_mlkit_text_recognition`, removed in T309 (PR #320). They are inert:
# release R8 reports no `com.google.mlkit.*` missing class and AGP's
# `build/app/outputs/mapping/release/missing_rules.txt` carries no ML Kit entry.
#
# Latin OCR is unaffected: it keeps using the bundled
# `com.google.mlkit:text-recognition:16.0.1` implementation dependency.
# If a Dart ML Kit wrapper is ever reintroduced, regenerate the rules from
# `missing_rules.txt` instead of restoring these lines.
#
# The file stays in place (Flutter adds it only when it exists,
# FlutterPlugin.kt) so the T003 evidence trail keeps resolving.
