// T125 no-completeness-claim audit (US8 scenario 5; FR-085;
// `contracts/error-catalog.de.md` §2).
//
// Evidence class: NONE. Host-VM tests on the shipped ARB, the generated
// localizations, and the shipped US8 summary/failure widgets. They open no
// platform channel and make no Android, browser, or recognition-quality
// claim.
//
// What is asserted, and only that:
//   * negative — no user-facing German text in the ARB, the generated
//     localization class, or the rendered US8 surfaces contains the exact
//     completeness claim phrases „vollständig erkannt“, „fehlerfrei“, or
//     „fehlerlos erkannt“;
//   * positive — the honest vocabulary is present instead: summary rows use
//     „Vorschläge“, „unsicher“, „bestätigt“/„übernommen“, and the summary
//     renders the mandatory no-completeness note;
//   * pattern — the same negative assertions on exact texts as the T059
//     honesty pattern: strings are compared verbatim, never by substring
//     of a normalized form that could hide a claim.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_app/features/editor/page_failure.dart';
import 'package:feldexa_app/features/editor/recognition_summary.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/package_root.dart';

/// Exact completeness-claim phrases that no user-facing surface may state
/// or imply (error catalog §2; FR-085). Matched case-insensitively so a
/// sentence-initial capital cannot smuggle a claim through.
const List<String> _forbiddenCompletenessClaims = <String>[
  'vollständig erkannt',
  'fehlerfrei',
  'fehlerlos erkannt',
  'vollständig automatisch erkannt',
];

/// Standalone completeness claims with word boundaries (P3 fix). The
/// legitimate forms „unvollständig“, „vollständigen Dokuments“ (IMP-006)
/// and „nicht vollständig abgeschlossen“ do not match: `\bvollständig\b`
/// requires a non-word character right after the bare adjective.
final List<RegExp> _forbiddenClaimPatterns = <RegExp>[
  RegExp(r'\bvollständig\s+(erkannt|geprüft|erfasst)\b', caseSensitive: false),
  RegExp(r'\bist\s+vollständig\b', caseSensitive: false),
  RegExp(r'\bvollständig\.\s*$'),
];

bool _claimsCompleteness(String text) {
  final String lower = text.toLowerCase();
  if (_forbiddenCompletenessClaims.any(lower.contains)) {
    return true;
  }
  return _forbiddenClaimPatterns.any(
    (RegExp pattern) => pattern.hasMatch(text),
  );
}

Map<String, dynamic> _readArb() {
  return jsonDecode(
    File('${packageRoot.path}/lib/l10n/app_de.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
}

Iterable<String> _arbUserTexts() {
  final Map<String, dynamic> arb = _readArb();
  return arb.keys
      .where((String key) => !key.startsWith('@'))
      .map((String key) => arb[key] as String);
}

FieldSuggestion _suggestion({
  required String ordinal,
  required double confidence,
  SuggestionResolution resolution = SuggestionResolution.unresolved,
}) {
  return FieldSuggestion(
    id: 's_p0_$ordinal',
    pageIndex: 0,
    rect: Rect.fromLTWH(10, 10, 100, 20),
    proposedType: FieldType.text,
    confidence: confidence,
    labelText: 'Name',
    evidence: SuggestionEvidence(
      cues: const <SuggestionCue>[SuggestionCue.box],
    ),
    resolution: resolution,
  );
}

ConfirmedField _confirmed({
  required String ordinal,
  required Provenance provenance,
}) {
  return ConfirmedField(
    id: provenance == Provenance.machine
        ? 'aaaa2222-2222-4222-8222-2222222221$ordinal'
        : 'aaaaaaaa-2222-4222-8222-2222222222$ordinal',
    pageIndex: 0,
    rect: Rect.fromLTWH(10, 10, 100, 20),
    type: FieldType.text,
    provenance: provenance,
    label: 'Feld $ordinal',
    order: 0,
    createdAt: DateTime.utc(2026, 11, 27, 12),
    updatedAt: DateTime.utc(2026, 11, 27, 12),
    sourceSuggestionId: provenance == Provenance.machine ? 's_p0_0001' : null,
    suggestionConfidence: provenance == Provenance.machine ? 0.80 : null,
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('de'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('ARB and generated localizations carry no completeness claim', () {
    test('no ARB user-facing text states a completeness claim', () {
      for (final String text in _arbUserTexts()) {
        expect(
          _claimsCompleteness(text),
          isFalse,
          reason: 'ARB text claims completeness: "$text"',
        );
      }
    });

    test('sentence-initial and standalone claims are caught too', () {
      // The patterns must fail a future claim, including capitalized ones,
      // while the legitimate forms stay allowed.
      expect(_claimsCompleteness('Die Erkennung ist vollständig.'), isTrue);
      expect(_claimsCompleteness('Vollständig erkannt: 12'), isTrue);
      expect(_claimsCompleteness('Fehlerfrei.'), isTrue);
      expect(_claimsCompleteness('Alle Felder vollständig geprüft.'), isTrue);
      expect(
        _claimsCompleteness(
          'Ein Export des vollständigen Dokuments ist dadurch beeinträchtigt.',
        ),
        isFalse,
        reason: 'IMP-006 legitimately speaks of the complete document',
      );
      expect(
        _claimsCompleteness(
          'Die Erkennung ist unvollständig, bis Sie alle Vorschläge geprüft '
          'haben.',
        ),
        isFalse,
      );
    });

    test('the generated German localization class states no claim', () {
      final File generated = File(
        '${packageRoot.path}/lib/l10n/app_localizations_de.dart',
      );
      final String source = generated.readAsStringSync();
      for (final String line in source.split('\n')) {
        expect(
          _claimsCompleteness(line),
          isFalse,
          reason: 'generated localization line states a claim: "$line"',
        );
      }
    });

    test('the honest summary vocabulary is present in the ARB', () {
      final Map<String, dynamic> arb = _readArb();
      expect(arb['recognitionSummaryOpen'], contains('Vorschläge'));
      expect(arb['recognitionSummaryUncertain'], contains('unsicher'));
      expect(arb['recognitionSummaryAdopted'], contains('Übernommene'));
      expect(arb['recognitionSummaryNote'], contains('unvollständig'));
    });
  });

  group('the rendered US8 summary claims no completeness', () {
    testWidgets('summary rows and note stay inside the honest vocabulary', (
      WidgetTester tester,
    ) async {
      final RecognitionSummaryCounts counts =
          RecognitionSummaryCounts.fromParts(
            <ConfirmedField>[
              _confirmed(ordinal: 'aa', provenance: Provenance.user),
              _confirmed(ordinal: 'bb', provenance: Provenance.machine),
            ],
            <FieldSuggestion>[
              _suggestion(ordinal: '0001', confidence: 0.30),
              _suggestion(ordinal: '0002', confidence: 0.90),
            ],
          );
      await tester.pumpWidget(_host(RecognitionSummary(counts: counts)));

      expect(
        find.byKey(const ValueKey<String>(recognitionSummaryKey)),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>(recognitionSummaryNoteKey)),
        findsOneWidget,
      );
      expect(find.textContaining('Vorschläge'), findsWidgets);
      expect(find.textContaining('unsicher'), findsWidgets);
      // P3 fix: the four rows are asserted verbatim, so a manual/adopted
      // swap or a template mis-count cannot pass.
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(RecognitionSummary)),
      );
      expect(find.text(l10n.recognitionSummaryManual(1)), findsOneWidget);
      expect(find.text(l10n.recognitionSummaryAdopted(1)), findsOneWidget);
      expect(find.text(l10n.recognitionSummaryTemplate(0)), findsOneWidget);
      expect(
        find.text(
          '${l10n.recognitionSummaryOpen(2)} '
          '${l10n.recognitionSummaryUncertain(1)}',
        ),
        findsOneWidget,
      );

      for (final Text text in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(RecognitionSummary),
          matching: find.byType(Text),
        ),
      )) {
        final String? rendered = text.data;
        if (rendered == null) {
          continue;
        }
        expect(
          _claimsCompleteness(rendered),
          isFalse,
          reason: 'summary renders completeness claim: "$rendered"',
        );
      }
    });

    testWidgets('rejected suggestions never count as open', (
      WidgetTester tester,
    ) async {
      final RecognitionSummaryCounts counts =
          RecognitionSummaryCounts.fromParts(
            const <ConfirmedField>[],
            <FieldSuggestion>[
              _suggestion(
                ordinal: '0003',
                confidence: 0.90,
                resolution: SuggestionResolution.rejected,
              ),
            ],
          );
      expect(counts.open, 0);
      expect(counts.openUncertain, 0);
      await tester.pumpWidget(_host(RecognitionSummary(counts: counts)));
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(RecognitionSummary)),
      );
      expect(find.text(l10n.recognitionSummaryOpen(0)), findsOneWidget);
    });

    testWidgets('the empty summary still disclaims completeness', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          RecognitionSummary(
            counts: RecognitionSummaryCounts.fromParts(
              const <ConfirmedField>[],
              const <FieldSuggestion>[],
            ),
          ),
        ),
      );
      expect(find.textContaining('unvollständig'), findsOneWidget);
    });
  });

  group('IMP-006 pages keep exactly one warning surface', () {
    late AppLocalizations l10n;

    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('de'));
    });

    core.Page pageFixture({
      required int index,
      core.AnalysisState analysis = core.AnalysisState.complete,
      bool unreadable = false,
      String? messageKey,
    }) {
      return core.Page(
        index: index,
        geometry: core.PageGeometry(
          mediaBox: core.Rect.fromLTWH(0, 0, 595, 842),
        ),
        analysis: analysis,
        unreadable: unreadable,
        failure: messageKey == null
            ? null
            : core.PageFailure(
                pageIndex: index,
                category: core.PageFailureCategory.unsupportedStructure,
                messageKey: messageKey,
              ),
      );
    }

    test('the projection excludes IMP-006 and unreadable pages', () {
      // P2 fix: an import-unreadable page is persisted as `failed` with
      // IMP-006; the existing T044 warning must stay the only rendering.
      final List<PageFailureExplanation> notices =
          recognitionFailureExplanations(l10n, <core.Page>[
            pageFixture(
              index: 0,
              messageKey: 'REC-002',
              analysis: core.AnalysisState.failed,
            ),
            pageFixture(
              index: 1,
              unreadable: true,
              messageKey: 'IMP-006',
              analysis: core.AnalysisState.failed,
            ),
            pageFixture(
              index: 2,
              messageKey: 'IMP-006',
              analysis: core.AnalysisState.failed,
            ),
            pageFixture(
              index: 3,
              messageKey: 'REC-003',
              analysis: core.AnalysisState.failed,
            ),
          ]);
      expect(
        notices.map((PageFailureExplanation notice) => notice.code),
        <String>['REC-002', 'REC-003'],
        reason: 'IMP-006 must not produce a second notice',
      );
    });

    test('a fully import-unreadable document produces no REC notices', () {
      expect(
        recognitionFailureExplanations(l10n, <core.Page>[
          pageFixture(
            index: 0,
            unreadable: true,
            messageKey: 'IMP-006',
            analysis: core.AnalysisState.failed,
          ),
          pageFixture(
            index: 1,
            unreadable: true,
            messageKey: 'IMP-006',
            analysis: core.AnalysisState.failed,
          ),
        ]),
        isEmpty,
      );
    });
  });

  group('failed-page explanations never imply a complete document', () {
    late AppLocalizations l10n;

    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('de'));
    });

    test('REC-002 explanation states the failure and the unchanged pages', () {
      final PageFailureExplanation? explanation = explainPageFailure(
        l10n,
        pageIndex: 1,
        messageKey: 'REC-002',
      );
      expect(explanation, isNotNull);
      expect(explanation!.message, l10n.rec002(2));
      expect(explanation.message, contains('fehlgeschlagen'));
      expect(explanation.recovery, l10n.rec002Recovery);
    });

    test('REC-003 explanation explains the unsupported structure', () {
      final PageFailureExplanation? explanation = explainPageFailure(
        l10n,
        pageIndex: 0,
        messageKey: 'REC-003',
      );
      expect(explanation, isNotNull);
      expect(explanation!.message, l10n.rec003(1));
      expect(explanation.recovery, l10n.rec003Recovery);
    });

    test('unknown and null keys produce no invented explanation', () {
      expect(explainPageFailure(l10n, pageIndex: 0, messageKey: null), isNull);
      expect(
        explainPageFailure(l10n, pageIndex: 0, messageKey: 'REC-999'),
        isNull,
      );
    });

    testWidgets('the failure notice renders message and recovery verbatim', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          PageFailureNotice(
            explanation: explainPageFailure(
              l10n,
              pageIndex: 2,
              messageKey: 'REC-002',
            )!,
          ),
        ),
      );
      expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('page-failure-notice-REC-002')),
        findsOneWidget,
      );
      for (final String forbidden in _forbiddenCompletenessClaims) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });
  });
}
