# T003 release R8 rules — ML Kit rules emptied by T321B (2026-11-24).
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

# T326 (Issue #326): the optional JPEG 2000 codec of pdfbox-android.
#
# `com.gemalto.jp2.JP2Decoder` belongs to JP2Android, an optional codec that
# `com.tom-roush:pdfbox-android:2.0.27.0` never declares and that is absent from
# this build's dependency graph. The reference becomes reachable as soon as the
# app really uses PDFBox (T039 preflight, T040 decryption): pdfbox's
# `FilterFactory` constructor instantiates `JPXFilter` unconditionally, so R8
# sees `JPXFilter.readJPX` and its `com.gemalto.jp2.JP2Decoder` reference.
#
# Suppressing the warning does not weaken a runtime check: `readJPX` probes the
# codec with `Class.forName("com.gemalto.jp2.JP2Decoder")` and raises the
# library's own `MissingImageReaderException("Cannot read JPX image: JP2Android
# is not installed.")` when it is missing — a defined IOException path, not a
# crash. Feldexa never decodes images from PDFs either: the app's PDFBox use is
# structural (`COSDictionary`/`COSName`/`PDDocument`/`PDPage`/`PDRectangle`,
# memory-only buffers, `InvalidPasswordException`), with no `PDFRenderer`,
# `PDFImageXObject` or text stripper. A JPXDecode stream never reaches
# `FilterFactory`, and if it ever did, the absent codec fails exactly as it does
# without this rule. No class is added to or kept out of the APK.
-dontwarn com.gemalto.jp2.JP2Decoder
