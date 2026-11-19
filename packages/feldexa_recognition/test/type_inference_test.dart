// T053 host-VM tests for label proximity and type inference.
//
// Normative sources: `specs/001-scanned-form-workflow/contracts/recognition-
// output.md` §2, §2.1, §3.1, §3.2, §3.5; `spec.md` FR-012; `data-model.md`
// §3.4. All fixtures are synthetic; no OCR engine, raster, detector, real
// document content, or persistence is used. The production oracle is
// `packages/feldexa_recognition/lib/src/type_inference.dart`; this file does
// not reimplement matching or typing rules.
@TestOn('vm')
library;

import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/suggestion_schema.dart';
import 'package:feldexa_recognition/src/type_inference.dart';
import 'package:flutter_test/flutter_test.dart';

const double _pageWidthPt = 400;
const double _pageHeightPt = 400;
const double _medianPt = 12;

DisplayRect _rect(double x, double y, double width, double height) {
  return DisplayRect(x: x, y: y, width: width, height: height);
}

GeometryCandidate _candidate({
  DisplayRect? rect,
  List<String> cues = const <String>['underline'],
  double inkCoverage = 0.02,
}) {
  return GeometryCandidate(
    rect: rect ?? _rect(100, 100, 120, 12),
    cues: cues,
    inkCoverage: inkCoverage,
  );
}

LabelObservation _label(
  String text, {
  double x = 100,
  double y = 100,
  double width = 40,
  double height = 10,
  double confidence = 0.9,
}) {
  return LabelObservation(
    text: text,
    rect: _rect(x, y, width, height),
    ocrConfidence: confidence,
  );
}

TypeInferenceResult _infer({
  GeometryCandidate? candidate,
  List<LabelObservation> labels = const <LabelObservation>[],
  double singleLineMedianHeightPt = _medianPt,
  double pageWidthPt = _pageWidthPt,
  double pageHeightPt = _pageHeightPt,
}) {
  return TypeInference.infer(
    candidate: candidate ?? _candidate(),
    labels: labels,
    singleLineMedianHeightPt: singleLineMedianHeightPt,
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
}

void main() {
  group('lexicon v1 classification and cues', () {
    test('every token maps to its documented §3.2 class', () {
      const Map<String, String> forcedType = <String, String>{
        // date keywords
        'geburtsdatum': 'date',
        'datum': 'date',
        'jahr': 'date',
        // explicit numeric keywords
        'betrag': 'number',
        'summe': 'number',
        'iban': 'number',
        'steuernummer': 'number',
        // §3.2 text-guarded numeric and date labels
        'plz': 'text',
        'telefon': 'text',
        'monat': 'text',
        'zeitraum': 'text',
        'von': 'text',
        'bis': 'text',
        // signature keywords
        'unterschrift': 'signature',
        'datum/unterschrift': 'signature',
      };
      const Set<String> neutral = <String>{
        'name',
        'vorname',
        'nachname',
        'familienname',
        'geburtsort',
        'straße',
        'strasse',
        'hausnummer',
        'ort',
        'wohnort',
        'postleitzahl',
        'telefax',
        'e-mail',
        'email',
        'bic',
        'bank',
        'konto',
        'steuer-id',
        'aktenzeichen',
        'geschäftszeichen',
        'antrag',
      };
      expect(
        forcedType.length + neutral.length,
        SuggestionSchema.keywordLexiconV1.length,
      );
      expect(<String>{
        ...forcedType.keys,
        ...neutral,
      }, SuggestionSchema.keywordLexiconV1.toSet());

      // The checkbox geometry would win for neutral keywords, proving that a
      // matching typed keyword really forced date/number/text/signature.
      final GeometryCandidate checkbox = _candidate(
        rect: _rect(100, 100, 12, 12),
      );
      for (final MapEntry<String, String> entry in forcedType.entries) {
        final TypeInferenceResult result = _infer(
          candidate: checkbox,
          labels: <LabelObservation>[_label(entry.key)],
        );
        expect(
          result.addedCues,
          contains('keyword_${entry.key}'),
          reason: entry.key,
        );
        expect(result.proposedType, entry.value, reason: entry.key);
      }
      for (final String key in neutral) {
        final TypeInferenceResult square = _infer(
          candidate: checkbox,
          labels: <LabelObservation>[_label(key)],
        );
        expect(square.addedCues, contains('keyword_$key'), reason: key);
        expect(square.proposedType, 'checkbox', reason: key);

        final TypeInferenceResult singleLine = _infer(
          labels: <LabelObservation>[_label(key)],
        );
        expect(singleLine.proposedType, 'text', reason: key);
      }
    });

    test('case and umlaut variants match while display text is preserved', () {
      final TypeInferenceResult upper = _infer(
        labels: <LabelObservation>[_label('GESCHÄFTSZEICHEN')],
      );
      expect(upper.addedCues, contains('keyword_geschäftszeichen'));
      expect(upper.labelText, 'GESCHÄFTSZEICHEN');
      expect(upper.proposedType, 'text');

      final TypeInferenceResult folded = _infer(
        labels: <LabelObservation>[_label('Geschaeftszeichen')],
      );
      expect(folded.addedCues, contains('keyword_geschäftszeichen'));
    });

    test('literal Straße/Strasse choose their own lexicon spelling', () {
      final TypeInferenceResult umlaut = _infer(
        labels: <LabelObservation>[_label('Straße')],
      );
      expect(umlaut.addedCues, contains('keyword_straße'));
      expect(umlaut.addedCues, isNot(contains('keyword_strasse')));
      expect(umlaut.labelText, 'Straße');

      final TypeInferenceResult ascii = _infer(
        labels: <LabelObservation>[_label('STRASSE')],
      );
      expect(ascii.addedCues, contains('keyword_strasse'));
      expect(ascii.addedCues, isNot(contains('keyword_straße')));
    });

    test('internal whitespace is preserved in labelText', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('  Name   des   Antragstellers  ')],
      );
      expect(result.labelText, 'Name   des   Antragstellers');
      expect(result.addedCues, contains('keyword_name'));
    });

    test('longest match avoids nested name, ort, and datum cues', () {
      final TypeInferenceResult vorname = _infer(
        labels: <LabelObservation>[_label('Vorname')],
      );
      expect(vorname.addedCues, contains('keyword_vorname'));
      expect(vorname.addedCues, isNot(contains('keyword_name')));

      final TypeInferenceResult geburtsort = _infer(
        labels: <LabelObservation>[_label('Geburtsort')],
      );
      expect(geburtsort.addedCues, contains('keyword_geburtsort'));
      expect(geburtsort.addedCues, isNot(contains('keyword_ort')));

      final TypeInferenceResult geburtsdatum = _infer(
        labels: <LabelObservation>[_label('Geburtsdatum')],
      );
      expect(geburtsdatum.addedCues, contains('keyword_geburtsdatum'));
      expect(geburtsdatum.addedCues, isNot(contains('keyword_datum')));
    });

    test('compound Datum/Unterschrift is one signature lexeme', () {
      final TypeInferenceResult result = _infer(
        candidate: _candidate(rect: _rect(100, 100, 12, 12)),
        labels: <LabelObservation>[_label('Datum/Unterschrift')],
      );
      expect(result.proposedType, 'signature');
      expect(result.addedCues, contains('keyword_datum/unterschrift'));
      expect(result.addedCues, isNot(contains('keyword_datum')));
      expect(result.addedCues, isNot(contains('keyword_unterschrift')));
    });

    test('word boundaries reject substrings', () {
      final TypeInferenceResult bisher = _infer(
        labels: <LabelObservation>[_label('bisher')],
      );
      expect(bisher.addedCues, isEmpty);

      final TypeInferenceResult name2 = _infer(
        labels: <LabelObservation>[_label('Name2')],
      );
      expect(name2.addedCues, isEmpty);

      final TypeInferenceResult mail = _infer(
        labels: <LabelObservation>[_label('E-Mail-Adresse')],
      );
      expect(mail.addedCues, contains('keyword_e-mail'));
      expect(mail.addedCues, isNot(contains('keyword_email')));
    });

    test('numeric-family keywords add numeric_context only', () {
      final TypeInferenceResult number = _infer(
        labels: <LabelObservation>[_label('Betrag')],
      );
      expect(number.addedCues, contains('numeric_context'));

      final TypeInferenceResult textGuarded = _infer(
        labels: <LabelObservation>[_label('PLZ')],
      );
      expect(textGuarded.addedCues, contains('numeric_context'));

      final TypeInferenceResult date = _infer(
        labels: <LabelObservation>[_label('Geburtsdatum')],
      );
      expect(date.addedCues, isNot(contains('numeric_context')));

      final TypeInferenceResult signature = _infer(
        labels: <LabelObservation>[_label('Unterschrift')],
      );
      expect(signature.addedCues, isNot(contains('numeric_context')));

      final TypeInferenceResult neutral = _infer(
        labels: <LabelObservation>[_label('Name')],
      );
      expect(neutral.addedCues, isNot(contains('numeric_context')));
    });

    test('postleitzahl and telefax are neutral, not forced text', () {
      final GeometryCandidate checkbox = _candidate(
        rect: _rect(100, 100, 12, 12),
      );
      for (final String word in <String>['Postleitzahl', 'Telefax']) {
        final TypeInferenceResult square = _infer(
          candidate: checkbox,
          labels: <LabelObservation>[_label(word)],
        );
        expect(square.proposedType, 'checkbox', reason: word);
        expect(
          square.addedCues,
          contains('keyword_${word.toLowerCase()}'),
          reason: word,
        );
        expect(square.addedCues, isNot(contains('numeric_context')));

        final TypeInferenceResult singleLine = _infer(
          labels: <LabelObservation>[_label(word)],
        );
        expect(singleLine.proposedType, 'text', reason: word);
      }
    });
  });

  group('date-guarded labels', () {
    test('Monat, Zeitraum, von, bis remain text and never date', () {
      final GeometryCandidate checkbox = _candidate(
        rect: _rect(100, 100, 12, 12),
      );
      for (final String word in <String>['Monat', 'Zeitraum', 'von', 'bis']) {
        final TypeInferenceResult result = _infer(
          candidate: checkbox,
          labels: <LabelObservation>[_label(word)],
        );
        expect(result.proposedType, 'text', reason: word);
        expect(
          result.addedCues,
          contains('keyword_${word.toLowerCase()}'),
          reason: word,
        );
        expect(result.addedCues, isNot(contains('date_context')));
        expect(result.addedCues, isNot(contains('numeric_context')));
      }
    });

    test('a date mask does not override the date guard', () {
      final TypeInferenceResult result = _infer(
        candidate: _candidate(rect: _rect(100, 100, 12, 12)),
        labels: <LabelObservation>[_label('Monat TT.MM.JJJJ')],
      );
      expect(result.proposedType, 'text');
      expect(result.addedCues, contains('keyword_monat'));
      expect(result.addedCues, contains('date_context'));
    });

    test('a date guard also suppresses a second date word', () {
      final TypeInferenceResult result = _infer(
        candidate: _candidate(rect: _rect(100, 100, 12, 12)),
        labels: <LabelObservation>[_label('Datum Monat')],
      );
      expect(result.proposedType, 'text');
      expect(result.addedCues, contains('keyword_datum'));
      expect(result.addedCues, contains('keyword_monat'));
    });
  });

  group('§3.2 precedence', () {
    test('explicit cues override keyword, geometry, and date mask', () {
      final TypeInferenceResult smallSquare = _infer(
        candidate: _candidate(
          rect: _rect(100, 100, 12, 12),
          cues: const <String>['small_square', 'signature_area'],
        ),
        labels: <LabelObservation>[_label('Geburtsdatum TT.MM.JJJJ')],
      );
      expect(smallSquare.proposedType, 'checkbox');
      expect(smallSquare.addedCues, contains('keyword_geburtsdatum'));
      expect(smallSquare.addedCues, contains('date_context'));

      final TypeInferenceResult signatureArea = _infer(
        candidate: _candidate(
          rect: _rect(100, 100, 12, 12),
          cues: const <String>['signature_area'],
        ),
        labels: <LabelObservation>[_label('Betrag')],
      );
      expect(signatureArea.proposedType, 'signature');
    });

    test('keyword typing precedes geometry', () {
      final GeometryCandidate square = _candidate(
        rect: _rect(100, 100, 12, 12),
      );
      final TypeInferenceResult number = _infer(
        candidate: square,
        labels: <LabelObservation>[_label('Betrag')],
      );
      expect(number.proposedType, 'number');

      final TypeInferenceResult date = _infer(
        candidate: square,
        labels: <LabelObservation>[_label('Datum')],
      );
      expect(date.proposedType, 'date');

      final TypeInferenceResult neutral = _infer(
        candidate: square,
        labels: <LabelObservation>[_label('Name')],
      );
      expect(neutral.proposedType, 'checkbox');
    });

    test('geometry precedence: multiline, checkbox, single-line', () {
      final TypeInferenceResult multiline = _infer(
        candidate: _candidate(rect: _rect(100, 100, 100, 30)),
      );
      expect(multiline.proposedType, 'multiline');

      final TypeInferenceResult checkbox = _infer(
        candidate: _candidate(rect: _rect(100, 100, 12, 12)),
      );
      expect(checkbox.proposedType, 'checkbox');

      final TypeInferenceResult singleLine = _infer();
      expect(singleLine.proposedType, 'text');
    });

    test('multiline thresholds are inclusive', () {
      final TypeInferenceResult atThreshold = _infer(
        candidate: _candidate(rect: _rect(100, 100, 80, 22)),
        singleLineMedianHeightPt: 10,
      );
      expect(atThreshold.proposedType, 'multiline');

      final TypeInferenceResult belowThreshold = _infer(
        candidate: _candidate(rect: _rect(100, 100, 80, 21.875)),
        singleLineMedianHeightPt: 10,
      );
      expect(belowThreshold.proposedType, 'text');
    });

    test('checkbox aspect and height thresholds are inclusive', () {
      final TypeInferenceResult narrow = _infer(
        candidate: _candidate(rect: _rect(100, 100, 15, 20)),
      );
      expect(narrow.proposedType, 'checkbox');

      final TypeInferenceResult wide = _infer(
        candidate: _candidate(rect: _rect(100, 100, 26.6, 20)),
      );
      expect(wide.proposedType, 'checkbox');

      final TypeInferenceResult tooTall = _infer(
        candidate: _candidate(rect: _rect(100, 100, 20.125, 20.125)),
      );
      expect(tooTall.proposedType, 'text');
    });

    test('geometry precedes the printed date mask', () {
      final TypeInferenceResult multiline = _infer(
        candidate: _candidate(rect: _rect(100, 100, 100, 30)),
        labels: <LabelObservation>[_label('TT.MM.JJJJ')],
      );
      expect(multiline.proposedType, 'multiline');
      expect(multiline.addedCues, contains('date_context'));

      final TypeInferenceResult checkbox = _infer(
        candidate: _candidate(rect: _rect(100, 100, 12, 12)),
        labels: <LabelObservation>[_label('TT.MM.JJJJ')],
      );
      expect(checkbox.proposedType, 'checkbox');
      expect(checkbox.addedCues, contains('date_context'));
    });

    test('date mask applies after single-line geometry', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('TT.MM.JJJJ')],
      );
      expect(result.proposedType, 'date');
      expect(result.addedCues, contains('date_context'));
      expect(result.labelText, 'TT.MM.JJJJ');
    });

    test('a candidate satisfying every rule follows §3.2 exactly', () {
      final TypeInferenceResult result = _infer(
        candidate: _candidate(
          rect: _rect(100, 100, 12, 12),
          cues: const <String>['small_square', 'signature_area', 'box'],
        ),
        labels: <LabelObservation>[_label('Geburtsdatum TT.MM.JJJJ')],
      );
      expect(result.proposedType, 'checkbox');
    });
  });

  group('printed date mask', () {
    test('TT.MM.JJJJ is accepted case-insensitively', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('tt.mm.jjjj')],
      );
      expect(result.proposedType, 'date');
      expect(result.addedCues, contains('date_context'));
    });

    test('a malformed mask does not become a date', () {
      for (final String text in <String>[
        'TT.MM.JJJ',
        'TT.MM.JJJJX',
        'TT-MM-JJJJ',
        '31.12.2025',
      ]) {
        final TypeInferenceResult result = _infer(
          labels: <LabelObservation>[_label(text)],
        );
        expect(result.proposedType, 'text', reason: text);
        expect(result.addedCues, isNot(contains('date_context')), reason: text);
      }
    });

    test(
      'any credible adjacent mask counts; the nearest label is displayed',
      () {
        final TypeInferenceResult result = _infer(
          labels: <LabelObservation>[
            _label('Name', y: 90, height: 10),
            _label('TT.MM.JJJJ', y: 80, height: 10),
          ],
        );
        expect(result.labelText, 'Name');
        expect(result.proposedType, 'date');
        expect(result.addedCues, contains('date_context'));
      },
    );

    test('a non-credible mask is ignored', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[
          _label('Name', y: 90, height: 10),
          _label('TT.MM.JJJJ', y: 300, height: 10),
        ],
      );
      expect(result.proposedType, 'text');
      expect(result.addedCues, isNot(contains('date_context')));
    });
  });

  group('label proximity', () {
    test('nearest credible label wins and only its evidence is used', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[
          _label('Name', y: 90, height: 10),
          _label('Betrag', x: 230, y: 100, width: 30),
        ],
      );
      expect(result.labelText, 'Name');
      expect(result.addedCues, contains('keyword_name'));
      expect(result.addedCues, isNot(contains('keyword_betrag')));
      expect(result.addedCues, isNot(contains('ocr_alignment_right')));
    });

    test('24 pt is the inclusive credibility boundary', () {
      final TypeInferenceResult atBoundary = _infer(
        labels: <LabelObservation>[_label('Name', x: 244, y: 100, width: 30)],
      );
      expect(atBoundary.labelText, 'Name');

      final TypeInferenceResult beyond = _infer(
        labels: <LabelObservation>[
          _label('Name', x: 244.125, y: 100, width: 30),
        ],
      );
      expect(beyond.labelText, isNull);
      expect(beyond.proposedType, 'text');
      expect(beyond.addedCues, isEmpty);
    });

    test('0.5 is the inclusive confidence boundary', () {
      final TypeInferenceResult atBoundary = _infer(
        labels: <LabelObservation>[_label('Name', confidence: 0.5)],
      );
      expect(atBoundary.labelText, 'Name');

      final TypeInferenceResult below = _infer(
        labels: <LabelObservation>[_label('Name', confidence: 0.499)],
      );
      expect(below.labelText, isNull);
      expect(below.addedCues, isEmpty);
    });

    test('empty, whitespace, and missing labels yield null and text', () {
      for (final String text in <String>['', '   ', '\n\t ']) {
        final TypeInferenceResult result = _infer(
          labels: <LabelObservation>[_label(text)],
        );
        expect(result.labelText, isNull, reason: text);
        expect(result.proposedType, 'text');
      }
      final TypeInferenceResult noLabels = _infer();
      expect(noLabels.labelText, isNull);
      expect(noLabels.proposedType, 'text');
      expect(noLabels.addedCues, isEmpty);
    });

    test('distance tie is broken by rect y, then rect x, then text', () {
      // Both labels have squared distance 576: one is 24 pt above, the other
      // 24 pt to the right. The smaller y wins.
      final LabelObservation smallerY = _label(
        'SmallerY',
        x: 100,
        y: 66,
        width: 20,
      );
      final LabelObservation largerY = _label(
        'LargerY',
        x: 244,
        y: 100,
        width: 20,
      );
      expect(
        _infer(labels: <LabelObservation>[largerY, smallerY]).labelText,
        'SmallerY',
      );

      // Same distance (18 pt horizontal, 14 pt vertical) and y; the smaller x
      // wins.
      final LabelObservation left = _label('Left', x: 72, y: 76, width: 10);
      final LabelObservation right = _label('Right', x: 238, y: 76, width: 10);
      expect(_infer(labels: <LabelObservation>[right, left]).labelText, 'Left');

      // Identical position/distance; the lexicographically smaller text wins.
      final LabelObservation beta = _label('Beta');
      final LabelObservation alpha = _label('Alpha');
      expect(
        _infer(labels: <LabelObservation>[beta, alpha]).labelText,
        'Alpha',
      );
    });

    test('input order does not change the result', () {
      final LabelObservation first = _label('Name', y: 90);
      final LabelObservation second = _label('Betrag', x: 230, y: 100);
      final LabelObservation third = _label('Ort', x: 50, y: 100);
      final TypeInferenceResult forward = _infer(
        labels: <LabelObservation>[first, second, third],
      );
      final TypeInferenceResult reverse = _infer(
        labels: <LabelObservation>[third, second, first],
      );
      final TypeInferenceResult shuffled = _infer(
        labels: <LabelObservation>[second, first, third],
      );
      expect(reverse, forward);
      expect(shuffled, forward);
    });
  });

  group('alignment cues', () {
    test('a label left of the candidate gets the right cue', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('Betrag', x: 50, y: 101, width: 40)],
      );
      expect(result.addedCues, <String>[
        'keyword_betrag',
        'numeric_context',
        'ocr_alignment_right',
      ]);
    });

    test('a label above the candidate gets the below cue', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('Name', x: 100, y: 70, width: 40)],
      );
      expect(result.addedCues, <String>['keyword_name', 'ocr_alignment_below']);
    });

    test('a label to the right does not get the right cue', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('Name', x: 220, y: 101, width: 50)],
      );
      expect(result.addedCues, isNot(contains('ocr_alignment_right')));
      expect(result.addedCues, isNot(contains('ocr_alignment_below')));
      expect(result.addedCues, isNot(contains('label_below')));
    });

    test('a directly below label gets label_below only', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('Name', x: 100, y: 112, width: 120)],
      );
      expect(result.addedCues, <String>['keyword_name', 'label_below']);
      expect(result.addedCues, isNot(contains('ocr_alignment_below')));
    });

    test('an offset below label gets no alignment cue', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('Name', x: 230, y: 112, width: 30)],
      );
      expect(result.addedCues, <String>['keyword_name']);
      expect(result.addedCues, isNot(contains('ocr_alignment_below')));
      expect(result.addedCues, isNot(contains('label_below')));
    });

    test('label_below requires half of the narrower horizontal overlap', () {
      final TypeInferenceResult half = _infer(
        labels: <LabelObservation>[_label('Name', x: 160, y: 112, width: 100)],
      );
      expect(half.addedCues, contains('label_below'));

      final TypeInferenceResult justUnderHalf = _infer(
        labels: <LabelObservation>[_label('Name', x: 171, y: 112, width: 100)],
      );
      expect(justUnderHalf.addedCues, isNot(contains('label_below')));
      expect(justUnderHalf.addedCues, isNot(contains('ocr_alignment_below')));
    });

    test('ocr_alignment_below requires horizontal overlap', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('Name', x: 230, y: 70, width: 30)],
      );
      expect(result.addedCues, <String>['keyword_name']);
      expect(result.addedCues, isNot(contains('ocr_alignment_below')));
    });
  });

  group('labelText trimming and truncation', () {
    test('leading and trailing whitespace is trimmed', () {
      expect(
        _infer(labels: <LabelObservation>[_label('  Name  ')]).labelText,
        'Name',
      );
    });

    test('exactly 200 code points are preserved', () {
      final String text = 'a' * 200;
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label(text)],
      );
      expect(result.labelText, text);
      expect(result.labelText!.runes.length, 200);
    });

    test(
      'more than 200 code points are truncated without a trailing space',
      () {
        final TypeInferenceResult result = _infer(
          labels: <LabelObservation>[_label('a' * 199 + '   b')],
        );
        expect(result.labelText, 'a' * 199);
        expect(result.labelText, result.labelText!.trim());
      },
    );

    test('truncation counts code points, not UTF-16 code units', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('😀' * 250)],
      );
      expect(result.labelText!.runes.length, 200);
      expect(result.labelText, '😀' * 200);
    });

    test('a long whitespace tail is trimmed before truncation', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('Name${' ' * 300}')],
      );
      expect(result.labelText, 'Name');
    });
  });

  group('result contract and determinism', () {
    test('proposedType is always a SuggestionSchema proposed type', () {
      final List<TypeInferenceResult> results = <TypeInferenceResult>[
        _infer(),
        _infer(labels: <LabelObservation>[_label('Betrag')]),
        _infer(labels: <LabelObservation>[_label('Datum')]),
        _infer(labels: <LabelObservation>[_label('TT.MM.JJJJ')]),
        _infer(candidate: _candidate(rect: _rect(100, 100, 12, 12))),
        _infer(candidate: _candidate(rect: _rect(100, 100, 100, 30))),
        _infer(
          candidate: _candidate(cues: const <String>['signature_area']),
          labels: <LabelObservation>[_label('Betrag')],
        ),
      ];
      for (final TypeInferenceResult result in results) {
        expect(SuggestionSchema.proposedTypes, contains(result.proposedType));
      }
    });

    test('added cues are sorted, unique, and unmodifiable', () {
      final TypeInferenceResult result = _infer(
        labels: <LabelObservation>[_label('IBAN', x: 50, y: 100, width: 40)],
      );
      expect(result.addedCues, <String>[
        'keyword_iban',
        'numeric_context',
        'ocr_alignment_right',
      ]);
      for (int index = 0; index + 1 < result.addedCues.length; index++) {
        expect(
          result.addedCues[index].compareTo(result.addedCues[index + 1]),
          lessThan(0),
        );
      }
      expect(() => result.addedCues.add('box'), throwsUnsupportedError);
    });

    test('equal inputs produce equal results and hashes', () {
      final TypeInferenceResult first = _infer(
        labels: <LabelObservation>[_label('Name')],
      );
      final TypeInferenceResult second = _infer(
        labels: <LabelObservation>[_label('Name')],
      );
      expect(second, first);
      expect(second.hashCode, first.hashCode);
    });

    test('type inference alone cannot create a suggestion or drop a cue', () {
      final GeometryCandidate candidate = _candidate(
        cues: const <String>['box', 'underline'],
      );
      final List<String> originalCues = List<String>.of(candidate.cues);
      final TypeInferenceResult result = _infer(
        candidate: candidate,
        labels: <LabelObservation>[_label('Name')],
      );

      // The candidate is immutable and its geometric evidence is untouched.
      expect(candidate.cues, originalCues);
      expect(candidate.cues, contains('underline'));
      expect(candidate.cues, contains('box'));

      // Inference only adds label evidence. It exposes no id, confidence,
      // uncertainty, conflict, resolution, envelope, or persistence state.
      expect(result.addedCues, isNot(contains('underline')));
      expect(result.addedCues, isNot(contains('box')));
      expect(result.proposedType, 'text');
      expect(result.labelText, 'Name');
    });
  });

  group('invalid inputs are content-free', () {
    test('non-finite or out-of-range label confidence is rejected', () {
      for (final double confidence in <double>[
        double.nan,
        double.infinity,
        -0.01,
        1.01,
      ]) {
        expect(
          () => _label('SECRET_LABEL', confidence: confidence),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.message.toString(),
              'message',
              isNot(contains('SECRET')),
            ),
          ),
        );
      }
    });

    test('invalid median and page metrics are rejected', () {
      for (final double median in <double>[
        double.nan,
        double.infinity,
        0,
        -1,
      ]) {
        expect(
          () => _infer(singleLineMedianHeightPt: median),
          throwsArgumentError,
        );
      }
      for (final double width in <double>[double.nan, double.infinity, 0, -1]) {
        expect(() => _infer(pageWidthPt: width), throwsArgumentError);
      }
      for (final double height in <double>[
        double.nan,
        double.infinity,
        0,
        -1,
      ]) {
        expect(() => _infer(pageHeightPt: height), throwsArgumentError);
      }
    });

    test('rectangles outside the page are rejected content-free', () {
      expect(
        () => _infer(candidate: _candidate(rect: _rect(390, 100, 20, 12))),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message.toString(),
            'message',
            isNot(contains('SECRET')),
          ),
        ),
      );
      expect(
        () => _infer(
          labels: <LabelObservation>[
            LabelObservation(
              text: 'SECRET_LABEL',
              rect: _rect(390, 100, 20, 10),
              ocrConfidence: 0.9,
            ),
          ],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message.toString(),
            'message',
            isNot(contains('SECRET')),
          ),
        ),
      );
    });
  });
}
