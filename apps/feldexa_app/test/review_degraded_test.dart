// T075 degraded-detection review tests (issue #75).
//
// Evidence class: NONE. These are host-VM widget tests on the shipped widgets
// with an in-memory revision. They open no store, PDF, platform channel,
// emulator, or device and make no Android, IME, screen-reader, or visual claim.
//
// Normative sources:
//   * `specs/001-scanned-form-workflow/spec.md` FR-030 (a document stays fully
//     usable for review and filling when detection is incomplete, wrong, or
//     absent) and the US3 Independent Test;
//   * `contracts/editor-interactions.md` §3 (review badges, including the
//     `unsicher` uncertain badge) and §6 (the page strip shows every page with
//     its analysis state and unreadable/uncertain markers);
//   * `contracts/recognition-output.md` §3.4 (uncertainty presentation) and §7
//     (resolution and provenance invariants).
//
// What is asserted, and only what the shipped widgets show:
//   * honesty — an uncertain page carries the existing `unsicher` marker and
//     the strip renders no statement beyond the page number, its
//     analysis-state short form, and that marker;
//   * visibility — a low-confidence suggestion carries the existing `unsicher`
//     badge while a confident suggestion does not, and a page that produced no
//     suggestion shows the existing empty state instead of an invented field;
//   * usability — confirm, reject, rejection-undo, and a corrected value leave
//     every page, suggestion, field, and value intact;
//   * filling — a value entered on the degraded page survives a persisted
//     `RevisionContent` round trip and is reachable again.
//
// Composition
// -----------
// `EditorScreen` is not mounted: its uncertainty comes from a live analysis
// run. The test-local host below composes the same shipped widgets
// (`PageStrip`, the T077 `FieldSelectionSurface` hit test, the T069 overlay
// items, `SuggestionReviewPanel`, and `FieldValueSheet`) and drives the real
// application commands (`confirmSuggestion`, `rejectSuggestion`,
// `undoRejection`, `undoConfirmation`, `setFieldValue`) for every callback. The
// strip metadata mapping mirrors `EditorScreen._buildStripPagesFromContent`.
// No production file is touched by T075.
//
// `feldexa_ui` is consumed through the workspace package config, exactly as
// `EditorScreen` consumes it, so the dependency-declaration lint is ignored
// here rather than adding an unrequested `pubspec.yaml` entry.
//
// ignore_for_file: depend_on_referenced_packages

@TestOn('vm')
library;

import 'dart:async';

import 'package:feldexa_app/features/editor/field_value_sheet.dart';
import 'package:feldexa_app/features/editor/page_strip.dart';
import 'package:feldexa_app/features/editor/page_view.dart' as viewer;
import 'package:feldexa_app/features/editor/suggestion_review_panel.dart';
import 'package:feldexa_app/features/fill/text_control.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_application/src/review/confirm_suggestion.dart'
    as review;
import 'package:feldexa_application/src/review/set_value.dart' as set_value;
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:feldexa_ui/feldexa_ui.dart';
import 'package:flutter/material.dart' hide PageView;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic one-based suggestion ids for the degraded page (index 0).
const String _lowSuggestionId = 's_p0_0001';
const String _highSuggestionId = 's_p0_0002';

/// Lowercase UUIDv4 ids the review commands accept for generated fields.
const String _confirmedFieldId = '11111111-1111-4111-8111-111111111111';
const String _secondFieldId = '11111111-1111-4111-9111-111111111111';
const List<String> _fieldIds = <String>[_confirmedFieldId, _secondFieldId];

/// A4-free synthetic page box in PDF points; the tests use one square page.
const double _pageExtent = 300;
const Size _pageSize = Size(_pageExtent, _pageExtent);
const Rect _pageRect = Rect.fromLTWH(0, 0, _pageExtent, _pageExtent);

/// Stable key for the composed page surface the tests tap.
const String _pageSurfaceKey = 'degraded-page-surface';

/// The catalog word the page strip and the review panel both render.
const String _uncertainWord = 'unsicher';

final DateTime _editedAt = DateTime.utc(2026, 11, 21, 9, 30);
final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

core.Rect _lowRect() => core.Rect.fromLTWH(40, 60, 120, 20);
core.Rect _highRect() => core.Rect.fromLTWH(40, 120, 120, 20);

core.Page _page({
  required int index,
  core.AnalysisState analysis = core.AnalysisState.complete,
}) {
  return core.Page(
    index: index,
    geometry: core.PageGeometry(
      mediaBox: core.Rect.fromLTWH(0, 0, _pageExtent, _pageExtent),
    ),
    analysis: analysis,
    failure: analysis == core.AnalysisState.failed
        ? core.PageFailure(
            pageIndex: index,
            category: core.PageFailureCategory.unsupportedStructure,
            messageKey: 'REC-002',
          )
        : null,
  );
}

core.FieldSuggestion _suggestion({
  required String id,
  required core.FieldType type,
  required core.Rect rect,
  required double confidence,
  required String? labelText,
}) {
  return core.FieldSuggestion(
    id: id,
    pageIndex: 0,
    rect: rect,
    proposedType: type,
    confidence: confidence,
    labelText: labelText,
    evidence: core.SuggestionEvidence(
      cues: const <core.SuggestionCue>[core.SuggestionCue.underline],
      ocrUsed: false,
    ),
  );
}

/// A degraded document: page 1 is readable but its detection is uncertain,
/// page 2 failed to analyze at all. All weak suggestions sit on page 1, so
/// page 2 is the page without any suggestion.
core.RevisionContent _degradedContent() {
  return core.RevisionContent(
    pages: <core.Page>[
      _page(index: 0),
      _page(index: 1, analysis: core.AnalysisState.failed),
    ],
    suggestions: <core.FieldSuggestion>[
      _suggestion(
        id: _lowSuggestionId,
        type: core.FieldType.text,
        rect: _lowRect(),
        confidence: 0.32,
        labelText: 'Familienname',
      ),
      _suggestion(
        id: _highSuggestionId,
        type: core.FieldType.date,
        rect: _highRect(),
        confidence: 0.87,
        labelText: 'Geburtsdatum',
      ),
    ],
    fieldOrder: const <String>[],
  );
}

core.FieldSuggestion _suggestionById(core.RevisionContent content, String id) {
  return content.suggestions.singleWhere(
    (core.FieldSuggestion suggestion) => suggestion.id == id,
  );
}

void _useLogicalSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const <Locale>[Locale('de')],
    home: Scaffold(body: SafeArea(child: child)),
  );
}

/// The visible `Text` payloads inside [scope], in paint order.
///
/// Used to state exactly which words a shipped widget renders instead of
/// asserting a product claim the widget does not make.
List<String> _textsWithin(WidgetTester tester, Finder scope) {
  return <String>[
    for (final Text text in tester.widgetList<Text>(
      find.descendant(of: scope, matching: find.byType(Text)),
    ))
      text.data ?? '',
  ];
}

Finder _pageKey(int pageNumber) {
  return find.byKey(ValueKey<String>('page-strip-page-$pageNumber'));
}

Finder _rowKey(String suggestionId) {
  return find.byKey(ValueKey<String>('suggestion-row-$suggestionId'));
}

Finder _confirmKey(String suggestionId) {
  return find.byKey(ValueKey<String>('confirm-suggestion-$suggestionId'));
}

Finder _rejectKey(String suggestionId) {
  return find.byKey(ValueKey<String>('reject-suggestion-$suggestionId'));
}

final Finder _undoKey = find.byKey(const ValueKey<String>(undoReviewKey));

/// The page strip's own uncertain marker, scoped to one page control.
Finder _stripUncertain(int pageNumber) {
  return find.descendant(
    of: _pageKey(pageNumber),
    matching: find.text(_uncertainWord),
  );
}

/// Taps the centre of [rect] on the composed page surface.
Future<void> _tapField(WidgetTester tester, core.Rect rect) async {
  final Offset origin = tester.getTopLeft(
    find.byKey(const ValueKey<String>(_pageSurfaceKey)),
  );
  await tester.tapAt(
    origin + Offset(rect.left + rect.width / 2, rect.top + rect.height / 2),
  );
  await tester.pumpAndSettle();
}

_DegradedEditorState _hostState(WidgetTester tester) {
  return tester.state<_DegradedEditorState>(find.byType(_DegradedEditor));
}

void main() {
  testWidgets('an uncertain page is marked and claims nothing more', (
    WidgetTester tester,
  ) async {
    _useLogicalSurface(tester, const Size(900, 400));
    final SemanticsHandle handle = tester.ensureSemantics();
    final viewer.PageViewController
    viewerController = viewer.PageViewController(
      pages: <viewer.PageViewPageSize>[
        viewer.PageViewPageSize(widthPt: _pageExtent, heightPt: _pageExtent),
        viewer.PageViewPageSize(widthPt: _pageExtent, heightPt: _pageExtent),
      ],
    );
    addTearDown(viewerController.dispose);
    final PageStripController controller = PageStripController(
      viewer: viewerController,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 900,
            height: 200,
            child: PageStrip(
              controller: controller,
              pages: const <PageStripPage>[
                PageStripPage(
                  analysisState: PageStripAnalysisState.ready,
                  uncertain: true,
                ),
                PageStripPage(analysisState: PageStripAnalysisState.failed),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Page 1 is the uncertain page. Its visible words are exactly the page
    // number, the analysis-state short form, and the existing uncertain
    // marker: the strip renders no statement that detection found every field.
    expect(
      _textsWithin(tester, _pageKey(1)),
      unorderedEquals(<String>['1', _de.pageAnalysisComplete, _uncertainWord]),
    );
    // The page whose analysis failed stays plain: state word only, no marker.
    expect(
      _textsWithin(tester, _pageKey(2)),
      unorderedEquals(<String>['2', _de.pageAnalysisFailed]),
    );
    expect(
      find.descendant(of: _pageKey(2), matching: find.text(_uncertainWord)),
      findsNothing,
    );

    // The semantic hint appends the uncertainty instead of claiming
    // completeness, and the page stays navigable (FR-018).
    final SemanticsData uncertain = tester
        .getSemantics(_pageKey(1))
        .getSemanticsData();
    expect(uncertain.label, _de.a11yPageNavigation(1, 2));
    expect(uncertain.hint, '${_de.pageAnalysisCompleteHint}, $_uncertainWord');
    final SemanticsData failed = tester
        .getSemantics(_pageKey(2))
        .getSemanticsData();
    expect(failed.hint, _de.pageAnalysisFailedHint);

    controller.selectPage(1);
    await tester.pumpAndSettle();
    expect(controller.selectedPageIndex, 1);
    handle.dispose();
  });

  testWidgets('a low-confidence suggestion shows the uncertain badge', (
    WidgetTester tester,
  ) async {
    _useLogicalSurface(tester, const Size(420, 780));
    final core.RevisionContent content = _degradedContent();
    await tester.pumpWidget(
      _app(
        SuggestionReviewPanel(
          suggestions: content.suggestions,
          confirmedFieldCount: 0,
          onConfirm: (core.FieldSuggestion _) {},
          onReject: (core.FieldSuggestion _) {},
          onUndo: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_rowKey(_lowSuggestionId), findsOneWidget);
    expect(_rowKey(_highSuggestionId), findsOneWidget);

    // Only the weak suggestion carries the shipped `unsicher` badge; the
    // confident one shows its confidence without that claim.
    expect(
      find.descendant(
        of: _rowKey(_lowSuggestionId),
        matching: find.text(_uncertainWord),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _rowKey(_highSuggestionId),
        matching: find.text(_uncertainWord),
      ),
      findsNothing,
    );
    expect(find.text(_uncertainWord), findsOneWidget);
    expect(find.text(_de.suggestionConfidence(32)), findsOneWidget);
    expect(find.text(_de.suggestionConfidence(87)), findsOneWidget);

    // The header reports the real open count and zero confirmed fields; it
    // claims neither complete detection nor complete review.
    expect(find.text(_de.suggestionOpenCount(2)), findsOneWidget);
    expect(find.text(_de.suggestionFieldCount(0)), findsOneWidget);
    expect(find.text(_de.suggestionAllReviewed), findsNothing);
    expect(find.text(_de.suggestionEmpty), findsNothing);
  });

  testWidgets('a page without suggestions shows the empty state', (
    WidgetTester tester,
  ) async {
    _useLogicalSurface(tester, const Size(420, 780));
    final core.RevisionContent content = _degradedContent();
    // The review surface for page 2 only: that page produced no suggestion.
    final List<core.FieldSuggestion> pageTwo = <core.FieldSuggestion>[
      for (final core.FieldSuggestion suggestion in content.suggestions)
        if (suggestion.pageIndex == 1) suggestion,
    ];
    expect(pageTwo, isEmpty);
    expect(content.fields, isEmpty);

    await tester.pumpWidget(
      _app(
        SuggestionReviewPanel(
          suggestions: pageTwo,
          confirmedFieldCount: 0,
          onConfirm: (core.FieldSuggestion _) {},
          onReject: (core.FieldSuggestion _) {},
          onUndo: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The existing empty state, not an invented field or row.
    expect(
      find.byKey(const ValueKey<String>(suggestionEmptyKey)),
      findsOneWidget,
    );
    expect(find.text(_de.suggestionEmpty), findsOneWidget);
    expect(find.text(_de.suggestionAllReviewed), findsNothing);
    expect(find.text(_de.suggestionConfirmAction), findsNothing);
    expect(find.text(_de.suggestionRejectAction), findsNothing);
    expect(_rowKey(_lowSuggestionId), findsNothing);
    expect(_rowKey(_highSuggestionId), findsNothing);
  });

  testWidgets('confirm, reject, and undo keep the degraded document usable', (
    WidgetTester tester,
  ) async {
    _useLogicalSurface(tester, const Size(900, 1200));
    final core.RevisionContent base = _degradedContent();
    await tester.pumpWidget(
      _app(_DegradedEditor(content: base, uncertainPages: const <int>{0})),
    );
    await tester.pumpAndSettle();

    final _DegradedEditorState host = _hostState(tester);

    // The degraded page is visibly marked while review starts.
    expect(_stripUncertain(1), findsOneWidget);

    await tester.tap(_confirmKey(_lowSuggestionId));
    await tester.pumpAndSettle();

    expect(host.content.fields, hasLength(1));
    final core.ConfirmedField confirmed = host.content.fields.single;
    final core.FieldSuggestion low = _suggestionById(base, _lowSuggestionId);
    expect(confirmed.id, _confirmedFieldId);
    expect(confirmed.pageIndex, 0);
    expect(confirmed.type, core.FieldType.text);
    expect(confirmed.provenance, core.Provenance.machine);
    expect(confirmed.sourceSuggestionId, _lowSuggestionId);
    expect(confirmed.suggestionConfidence, 0.32);
    expect(confirmed.label, 'Familienname');
    // Confirmation preserves the recorded geometry instead of re-rounding it.
    expect(confirmed.rect, low.rect);
    expect(
      _suggestionById(host.content, _lowSuggestionId).resolution,
      core.SuggestionResolution.confirmed,
    );
    expect(
      _suggestionById(host.content, _highSuggestionId).resolution,
      core.SuggestionResolution.unresolved,
    );
    expect(find.text(_de.suggestionOpenCount(1)), findsOneWidget);
    expect(find.text(_de.suggestionFieldCount(1)), findsOneWidget);
    expect(find.text(_de.suggestionReviewProgress(1, 0)), findsOneWidget);
    // The honest page state is unchanged by a review action.
    expect(_stripUncertain(1), findsOneWidget);

    await tester.tap(_rejectKey(_highSuggestionId));
    await tester.pumpAndSettle();

    expect(
      _suggestionById(host.content, _highSuggestionId).resolution,
      core.SuggestionResolution.rejected,
    );
    expect(host.content.fields, hasLength(1));
    expect(find.text(_de.suggestionReviewProgress(1, 1)), findsOneWidget);
    // An empty queue after review says "reviewed", never "nothing detected".
    expect(find.text(_de.suggestionAllReviewed), findsOneWidget);
    expect(find.text(_de.suggestionEmpty), findsNothing);

    await tester.tap(_undoKey);
    await tester.pumpAndSettle();

    // The rejection is reversible and the confirmed field is untouched.
    expect(
      _suggestionById(host.content, _highSuggestionId).resolution,
      core.SuggestionResolution.unresolved,
    );
    expect(_rowKey(_highSuggestionId), findsOneWidget);
    expect(find.text(_de.suggestionOpenCount(1)), findsOneWidget);
    expect(find.text(_de.suggestionReviewProgress(1, 0)), findsOneWidget);
    expect(find.text(_de.suggestionFieldCount(1)), findsOneWidget);
    expect(host.content.suggestions, hasLength(2));
    expect(host.content.pages, hasLength(2));
    expect(host.content.fields.single.rect, low.rect);
    expect(host.canUndoReview, isTrue);
  });

  testWidgets('a corrected value on the degraded page loses no content', (
    WidgetTester tester,
  ) async {
    _useLogicalSurface(tester, const Size(900, 1200));
    await tester.pumpWidget(
      _app(
        _DegradedEditor(
          content: _degradedContent(),
          uncertainPages: const <int>{0},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final _DegradedEditorState host = _hostState(tester);
    await tester.tap(_confirmKey(_lowSuggestionId));
    await tester.pumpAndSettle();
    final core.RevisionContent confirmedContent = host.content;

    // Selecting the confirmed field on the degraded page opens the shipped
    // type-appropriate sheet with its validated save path.
    await _tapField(tester, _lowRect());
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Meier');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsNothing);

    final set_value.SetValueChange firstEntry = host.lastValueChange!;
    expect(firstEntry.fieldId, _confirmedFieldId);
    // The first entry replaced nothing, and the prior snapshot is retained.
    expect(firstEntry.previousValue, isNull);
    expect(firstEntry.previousContent.toJson(), confirmedContent.toJson());
    final core.RevisionContent afterFirst = host.content;
    expect(
      (afterFirst.values[_confirmedFieldId]! as core.TextValue).text,
      'Meier',
    );

    // Correcting the value again keeps the replaced content reachable instead
    // of silently discarding it.
    await _tapField(tester, _lowRect());
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text('Meier'), findsOneWidget);
    await tester.enterText(find.byKey(fieldTextControlInputKey), 'Müller');
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsNothing);

    final set_value.SetValueChange correction = host.lastValueChange!;
    expect(correction.previousValue, isA<core.TextValue>());
    expect((correction.previousValue! as core.TextValue).text, 'Meier');
    expect(correction.previousContent.toJson(), afterFirst.toJson());
    expect(
      (host.content.values[_confirmedFieldId]! as core.TextValue).text,
      'Müller',
    );

    // Everything else survived the corrections unchanged.
    final core.ConfirmedField field = host.content.fields.single;
    expect(field.id, _confirmedFieldId);
    expect(field.rect, _lowRect());
    expect(field.type, core.FieldType.text);
    expect(field.provenance, core.Provenance.machine);
    expect(field.label, 'Familienname');
    expect(
      <core.SuggestionResolution>[
        for (final core.FieldSuggestion suggestion in host.content.suggestions)
          suggestion.resolution,
      ],
      <core.SuggestionResolution>[
        core.SuggestionResolution.confirmed,
        core.SuggestionResolution.unresolved,
      ],
    );
    expect(host.content.pages, hasLength(2));
    // Filling a value never "repairs" the honest page state.
    expect(_stripUncertain(1), findsOneWidget);
  });

  testWidgets('a value entered on the degraded page survives a round trip', (
    WidgetTester tester,
  ) async {
    _useLogicalSurface(tester, const Size(900, 1200));
    await tester.pumpWidget(
      _app(
        _DegradedEditor(
          key: const ValueKey<String>('first-open'),
          content: _degradedContent(),
          uncertainPages: const <int>{0},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_confirmKey(_lowSuggestionId));
    await tester.pumpAndSettle();
    await _tapField(tester, _lowRect());
    await tester.enterText(
      find.byKey(fieldTextControlInputKey),
      'Müller & Söhne',
    );
    await tester.tap(find.byKey(fieldValueSaveKey));
    await tester.pumpAndSettle();

    final core.RevisionContent committed = _hostState(tester).content;
    expect(
      (committed.values[_confirmedFieldId]! as core.TextValue).text,
      'Müller & Söhne',
    );

    // The persisted form is exactly what a store read/write round trip yields.
    final core.RevisionContent reopened = core.RevisionContent.fromJson(
      committed.toJson(),
    );
    expect(reopened.toJson(), committed.toJson());

    await tester.pumpWidget(
      _app(
        _DegradedEditor(
          key: const ValueKey<String>('reopened'),
          content: reopened,
          uncertainPages: const <int>{0},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The reopened document is still honestly degraded: the uncertain marker,
    // the one open suggestion, and one confirmed field are all that is claimed.
    expect(_stripUncertain(1), findsOneWidget);
    expect(find.text(_de.suggestionOpenCount(1)), findsOneWidget);
    expect(find.text(_de.suggestionFieldCount(1)), findsOneWidget);
    expect(_rowKey(_highSuggestionId), findsOneWidget);
    expect(find.text(_de.suggestionAllReviewed), findsNothing);
    expect(find.text(_de.suggestionEmpty), findsNothing);

    // The stored value is still reachable for filling on the degraded page.
    await _tapField(tester, _lowRect());
    expect(find.byKey(fieldValueSheetKey), findsOneWidget);
    expect(find.text('Müller & Söhne'), findsOneWidget);
    await tester.tap(find.byKey(fieldValueCloseKey));
    await tester.pumpAndSettle();
    expect(find.byKey(fieldValueSheetKey), findsNothing);
  });
}

enum _UndoKind { rejection, confirmation }

/// One reversible review action, mirroring the editor's undo stack entry.
final class _ReviewUndo {
  const _ReviewUndo.rejection(this.suggestionId)
    : kind = _UndoKind.rejection,
      confirmedField = null;

  const _ReviewUndo.confirmation(this.suggestionId, this.confirmedField)
    : kind = _UndoKind.confirmation;

  final _UndoKind kind;
  final String suggestionId;
  final core.ConfirmedField? confirmedField;
}

/// Test-only composition host for the shipped degraded-detection surfaces.
///
/// It owns one in-memory `RevisionContent` (the snapshot the test treats as
/// persisted), the real `PageStrip` and `FieldSelectionSurface`, the review
/// panel, and the value sheet. Every callback applies the corresponding
/// application command; no store, clock, or id port participates.
final class _DegradedEditor extends StatefulWidget {
  const _DegradedEditor({
    required this.content,
    required this.uncertainPages,
    super.key,
  });

  /// The initial committed revision snapshot.
  final core.RevisionContent content;

  /// Zero-based page indices whose analysis is uncertain.
  final Set<int> uncertainPages;

  @override
  State<_DegradedEditor> createState() => _DegradedEditorState();
}

final class _DegradedEditorState extends State<_DegradedEditor> {
  late core.RevisionContent _content;
  late final viewer.PageViewController _viewerController;
  late final PageStripController _stripController;
  final FieldSelectionController _selection = FieldSelectionController();
  final List<_ReviewUndo> _undoStack = <_ReviewUndo>[];
  int _nextFieldId = 0;
  bool _sheetOpen = false;

  /// The current committed revision snapshot.
  core.RevisionContent get content => _content;

  /// The receipt of the last value commit, or null before one.
  set_value.SetValueChange? lastValueChange;

  /// Whether the review undo affordance has a reversible entry.
  bool get canUndoReview => _undoStack.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _content = widget.content;
    _viewerController = viewer.PageViewController(
      pages: <viewer.PageViewPageSize>[
        for (final core.Page page in _content.pages)
          viewer.PageViewPageSize(
            widthPt: page.geometry.displaySize.width,
            heightPt: page.geometry.displaySize.height,
          ),
      ],
    );
    _stripController = PageStripController(viewer: _viewerController);
  }

  @override
  void dispose() {
    _stripController.dispose();
    _viewerController.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PageStrip(controller: _stripController, pages: _stripPages()),
        const SizedBox(height: 8),
        SizedBox(
          key: const ValueKey<String>(_pageSurfaceKey),
          width: _pageExtent,
          height: _pageExtent,
          child: FieldSelectionSurface(
            controller: _selection,
            items: <FieldOverlayItem>[
              for (final core.ConfirmedField field in _content.fields)
                if (field.pageIndex == 0)
                  FieldOverlayItem.fromConfirmedField(field),
            ],
            pageSize: _pageSize,
            pageRect: _pageRect,
            onSelected: _handleSelection,
            child: const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: SuggestionReviewPanel(
            suggestions: _content.suggestions,
            confirmedFieldCount: _content.fields.length,
            onConfirm: _confirmSuggestion,
            onReject: _rejectSuggestion,
            onUndo: _undoLastReview,
            undoAvailable: _undoStack.isNotEmpty,
          ),
        ),
      ],
    );
  }

  /// Strip metadata, mirroring `EditorScreen._buildStripPagesFromContent`.
  List<PageStripPage> _stripPages() {
    return <PageStripPage>[
      for (final core.Page page in _content.pages)
        PageStripPage(
          analysisState: switch (page.analysis) {
            core.AnalysisState.pending => PageStripAnalysisState.pending,
            core.AnalysisState.running => PageStripAnalysisState.analyzing,
            core.AnalysisState.complete => PageStripAnalysisState.ready,
            core.AnalysisState.failed => PageStripAnalysisState.failed,
          },
          unreadable: page.unreadable,
          uncertain: widget.uncertainPages.contains(page.index),
        ),
    ];
  }

  void _handleSelection(FieldOverlayItem? item) {
    if (item == null) {
      _selection.clear();
      return;
    }
    for (final core.ConfirmedField field in _content.fields) {
      if (field.id == item.id) {
        unawaited(_openValueSheet(field));
        return;
      }
    }
  }

  Future<void> _openValueSheet(core.ConfirmedField field) async {
    if (_sheetOpen) {
      return;
    }
    _sheetOpen = true;
    try {
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (BuildContext context) {
          return FieldValueSheet(
            field: field,
            currentValue: _content.values[field.id],
            onCommit: (core.FieldValue value) => _saveValue(field, value),
          );
        },
      );
    } finally {
      _sheetOpen = false;
    }
  }

  Future<FieldValueCommitResult> _saveValue(
    core.ConfirmedField field,
    core.FieldValue value,
  ) async {
    final set_value.SetValueChange change;
    try {
      change = set_value.setFieldValue(
        _content,
        field.id,
        value: value,
        lastEditedAt: _editedAt,
      );
    } catch (_) {
      return FieldValueCommitResult.failed(
        AppLocalizations.of(context).save007,
      );
    }
    lastValueChange = change;
    setState(() {
      _content = change.content;
    });
    _selection.reconcile(
      _content.fields.map((core.ConfirmedField confirmed) => confirmed.id),
    );
    return const FieldValueCommitResult.saved();
  }

  void _confirmSuggestion(core.FieldSuggestion suggestion) {
    if (_nextFieldId >= _fieldIds.length) {
      return;
    }
    final review.SuggestionReviewChange change;
    try {
      change = review.confirmSuggestion(
        _content,
        suggestion.id,
        _fieldIds[_nextFieldId],
        suggestion.labelText ??
            _de.suggestionFieldLabel(_content.fields.length + 1),
        _editedAt,
      );
    } catch (_) {
      return;
    }
    final core.ConfirmedField? confirmed = change.confirmedField;
    if (confirmed == null) {
      return;
    }
    _nextFieldId++;
    setState(() {
      _content = change.content;
      _undoStack.add(_ReviewUndo.confirmation(change.suggestionId, confirmed));
    });
  }

  void _rejectSuggestion(core.FieldSuggestion suggestion) {
    final review.SuggestionReviewChange change;
    try {
      change = review.rejectSuggestion(_content, suggestion.id);
    } catch (_) {
      return;
    }
    setState(() {
      _content = change.content;
      _undoStack.add(_ReviewUndo.rejection(change.suggestionId));
    });
  }

  void _undoLastReview() {
    if (_undoStack.isEmpty) {
      return;
    }
    final _ReviewUndo undo = _undoStack.last;
    final review.SuggestionReviewChange change;
    try {
      change = switch (undo.kind) {
        _UndoKind.rejection => review.undoRejection(
          _content,
          undo.suggestionId,
        ),
        _UndoKind.confirmation => review.undoConfirmation(
          _content,
          undo.suggestionId,
          undo.confirmedField!,
        ),
      };
    } catch (_) {
      return;
    }
    setState(() {
      _content = change.content;
      _undoStack.removeLast();
    });
  }
}
