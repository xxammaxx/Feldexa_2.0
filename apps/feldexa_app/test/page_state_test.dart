@TestOn('vm')
library;

import 'package:feldexa_app/features/editor/page_state.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

/// T044 partially unreadable pages and the IMP-006 warning.
///
/// These are host-VM tests of a pure projection. They prove the per-page
/// readable/unreadable derivation, the suppression of the T040 1x1 placeholder,
/// the successful-with-warning result for a partial import, the explicit error
/// result for an all-unreadable source, the catalog-only German warning with
/// ascending 1-based page numbers, and the non-color-only status labels for the
/// page strip. They produce no `SIMULATED`, `EMULATOR`, or `DEVICE` evidence.
const String _imp006 = 'IMP-006';

/// Committed German resources, resolved through the generated ARB.
final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

/// A realistic A4 display size in PDF points.
final PageDisplaySize _a4 = PageDisplaySize(widthPt: 595.28, heightPt: 841.89);

/// The deterministic T040 placeholder box for a structurally unreadable page.
final PageDisplaySize _placeholder = PageDisplaySize(widthPt: 1, heightPt: 1);

PageStateInput _readable(
  int index, {
  PageAnalysisStatus analysis = PageAnalysisStatus.pending,
  PageDisplaySize? size,
}) {
  return PageStateInput(
    index: index,
    analysis: analysis,
    reportedDisplaySize: size ?? _a4,
  );
}

PageStateInput _unreadablePage(
  int index, {
  bool unreadable = true,
  bool withFailure = true,
  String messageKey = _imp006,
  PageAnalysisStatus analysis = PageAnalysisStatus.failed,
  PageDisplaySize? size,
}) {
  return PageStateInput(
    index: index,
    analysis: analysis,
    unreadable: unreadable,
    failureMessageKey: withFailure ? messageKey : null,
    reportedDisplaySize: size,
  );
}

/// The projection a later `Document`/editor integration performs.
PageStateInput _fromCorePage(core.Page page) {
  final core.Size size = page.geometry.displaySize;
  return PageStateInput(
    index: page.index,
    analysis: switch (page.analysis) {
      core.AnalysisState.pending => PageAnalysisStatus.pending,
      core.AnalysisState.running => PageAnalysisStatus.analyzing,
      core.AnalysisState.complete => PageAnalysisStatus.ready,
      core.AnalysisState.failed => PageAnalysisStatus.failed,
    },
    unreadable: page.unreadable,
    failureMessageKey: page.failure?.messageKey,
    reportedDisplaySize: PageDisplaySize(
      widthPt: size.width,
      heightPt: size.height,
    ),
  );
}

core.Page _corePage({
  required int index,
  required core.AnalysisState analysis,
  core.PageFailure? failure,
  bool unreadable = false,
  double width = 595.28,
  double height = 841.89,
}) {
  return core.Page(
    index: index,
    geometry: core.PageGeometry(
      mediaBox: core.Rect.fromLTWH(0, 0, width, height),
    ),
    analysis: analysis,
    failure: failure,
    unreadable: unreadable,
  );
}

void main() {
  group('readable pages', () {
    test('a pending page is readable with its reported display size', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[_readable(0)],
        localizations: _de,
      );

      final PageState page = result.pages.single;
      expect(page.pageIndex, 0);
      expect(page.pageNumber, 1);
      expect(page.analysis, PageAnalysisStatus.pending);
      expect(page.isUnreadable, isFalse);
      expect(page.isUsable, isTrue);
      expect(page.isAnalysisFailed, isFalse);
      expect(page.displaySize, isNotNull);
      expect(page.displaySize!.widthPt, 595.28);
      expect(page.displaySize!.heightPt, 841.89);
      expect(page.statusLabel, isNull);
      expect(page.failureMessageKey, isNull);
    });

    test('running analysis is projected as analyzing', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0, analysis: PageAnalysisStatus.analyzing),
        ],
        localizations: _de,
      );

      expect(result.pages.single.analysis, PageAnalysisStatus.analyzing);
      expect(result.pages.single.isUnreadable, isFalse);
      expect(result.pages.single.statusLabel, isNull);
    });

    test('complete analysis is projected as ready', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0, analysis: PageAnalysisStatus.ready),
        ],
        localizations: _de,
      );

      expect(result.pages.single.analysis, PageAnalysisStatus.ready);
      expect(result.pages.single.isUsable, isTrue);
    });

    test('a failed analysis stays readable, renderable, and labeled', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          PageStateInput(
            index: 1,
            analysis: PageAnalysisStatus.failed,
            failureMessageKey: 'REC-002',
            reportedDisplaySize: _a4,
          ),
        ],
        localizations: _de,
      );

      final PageState failed = result.pages[1];
      expect(failed.isUnreadable, isFalse);
      expect(failed.isUsable, isTrue);
      expect(failed.isAnalysisFailed, isTrue);
      expect(failed.displaySize, isNotNull);
      expect(failed.statusLabel, _de.rec002(2));
      expect(failed.failureMessageKey, 'REC-002');
      expect((result as PageStateSuccess).warning, isNull);
    });

    test('a fully readable document succeeds without a warning', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _readable(1, analysis: PageAnalysisStatus.analyzing),
          _readable(2, analysis: PageAnalysisStatus.ready),
        ],
        localizations: _de,
      );

      expect(result, isA<PageStateSuccess>());
      final PageStateSuccess success = result as PageStateSuccess;
      expect(result.isSuccess, isTrue);
      expect(result.isErrorState, isFalse);
      expect(success.warning, isNull);
      expect(success.isFullyReadable, isTrue);
      expect(success.isPartiallyUnreadable, isFalse);
      expect(success.isFullExportAffected, isFalse);
      expect(result.pages.map((PageState page) => page.pageNumber), <int>[
        1,
        2,
        3,
      ]);
      expect(result.readablePageCount, 3);
      expect(result.unreadablePageCount, 0);
      expect(result.unreadablePageNumbers, isEmpty);
    });
  });

  group('unreadable pages and the 1x1 placeholder', () {
    test('the placeholder page is unreadable and exposes no display size', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(1, size: _placeholder),
        ],
        localizations: _de,
      );

      final PageState page = result.pages[1];
      expect(page.pageNumber, 2);
      expect(page.isUnreadable, isTrue);
      expect(page.isUsable, isFalse);
      expect(page.displaySize, isNull);
      expect(page.statusLabel, _de.statusUnreadable);
      expect(page.failureMessageKey, _imp006);
      expect(result.unreadablePageNumbers, <int>[2]);
    });

    test('an unreadable page hides even a real-looking reported size', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(
            1,
            analysis: PageAnalysisStatus.pending,
            withFailure: false,
            size: _a4,
          ),
        ],
        localizations: _de,
      );

      final PageState page = result.pages[1];
      expect(page.isUnreadable, isTrue);
      expect(page.displaySize, isNull);
    });

    test('an unreadable page may omit its reported size', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[_readable(0), _unreadablePage(1)],
        localizations: _de,
      );

      expect(result.pages[1].isUnreadable, isTrue);
      expect(result.pages[1].displaySize, isNull);
    });

    test('an IMP-006 failure marks a page unreadable without the flag', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(1, unreadable: false, size: _placeholder),
        ],
        localizations: _de,
      );

      final PageState page = result.pages[1];
      expect(page.isUnreadable, isTrue);
      expect(page.displaySize, isNull);
      expect(page.statusLabel, _de.statusUnreadable);
    });

    test('the unreadable flag alone is sufficient', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(
            1,
            analysis: PageAnalysisStatus.pending,
            withFailure: false,
          ),
        ],
        localizations: _de,
      );

      expect(result.pages[1].isUnreadable, isTrue);
      expect(result.pages[1].analysis, PageAnalysisStatus.pending);
      expect(result.pages[1].displaySize, isNull);
    });

    test('a persisted T040 placeholder JSON page is suppressed', () {
      final core.Page persisted = core.Page.fromJson(<String, Object?>{
        'index': 1,
        'geometry': <String, Object?>{
          'mediaBox': <String, Object?>{
            'x': 0,
            'y': 0,
            'width': 1,
            'height': 1,
          },
          'cropBox': <String, Object?>{'x': 0, 'y': 0, 'width': 1, 'height': 1},
          'rotation': 0,
        },
        'analysis': 'failed',
        'failure': <String, Object?>{
          'pageIndex': 1,
          'category': 'unreadable',
          'messageKey': _imp006,
        },
        'unreadable': true,
      });

      expect(persisted.geometry.displaySize.width, 1);
      expect(persisted.geometry.displaySize.height, 1);

      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[_readable(0), _fromCorePage(persisted)],
        localizations: _de,
      );

      final PageState page = result.pages[1];
      expect(page.isUnreadable, isTrue);
      expect(page.displaySize, isNull);
      expect(page.statusLabel, _de.statusUnreadable);
      expect(result.unreadablePageNumbers, <int>[2]);
    });

    test('a readable 1x1 page is treated as its reported size', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[_readable(0, size: _placeholder)],
        localizations: _de,
      );

      final PageState page = result.pages.single;
      expect(page.isUnreadable, isFalse);
      expect(page.displaySize, isNotNull);
      expect(page.displaySize!.widthPt, 1);
      expect(page.displaySize!.heightPt, 1);
    });

    test(
      'pages are ordered and affected numbers are ascending and 1-based',
      () {
        final PageStateResult result = derivePageStates(
          pages: <PageStateInput>[
            _unreadablePage(2, size: _placeholder),
            _readable(0),
            _readable(3),
            _unreadablePage(1, size: _placeholder),
          ],
          localizations: _de,
        );

        expect(result.pages.map((PageState page) => page.pageIndex), <int>[
          0,
          1,
          2,
          3,
        ]);
        expect(result.unreadablePageNumbers, <int>[2, 3]);
        expect(
          result.unreadablePages.map((PageState page) => page.pageNumber),
          <int>[2, 3],
        );
      },
    );
  });

  group('IMP-006 warning presentation', () {
    test('a partially unreadable document succeeds with the warning', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(1, size: _placeholder),
          _readable(2),
          _unreadablePage(3, size: _placeholder),
        ],
        localizations: _de,
      );

      expect(result, isA<PageStateSuccess>());
      final PageStateSuccess success = result as PageStateSuccess;
      final PageStateWarning warning = success.warning!;

      expect(success.isSuccess, isTrue);
      expect(success.isErrorState, isFalse);
      expect(success.isPartiallyUnreadable, isTrue);
      expect(success.isFullyReadable, isFalse);
      expect(success.isFullExportAffected, isTrue);
      expect(warning.pageNumbers, <int>[2, 4]);
      expect(warning.message, _de.imp006('2, 4'));
      expect(warning.recovery, _de.imp006Recovery);
      expect(warning.affectsFullExport, isTrue);
    });

    test('affected pages are listed in ascending order', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _readable(1),
          _readable(2),
          _unreadablePage(3, size: _placeholder),
          _unreadablePage(4, size: _placeholder),
        ],
        localizations: _de,
      );

      final PageStateWarning warning = (result as PageStateSuccess).warning!;
      expect(warning.pageNumbers, <int>[4, 5]);
      expect(warning.message, _de.imp006('4, 5'));
    });

    test('a single affected page uses its 1-based number', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(1, size: _placeholder),
          _readable(2),
        ],
        localizations: _de,
      );

      final PageStateWarning warning = (result as PageStateSuccess).warning!;
      expect(warning.pageNumbers, <int>[2]);
      expect(warning.message, _de.imp006('2'));
    });

    test('warning text is catalog German without codes or paths', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(1, size: _placeholder),
        ],
        localizations: _de,
      );

      final PageStateWarning warning = (result as PageStateSuccess).warning!;
      for (final String text in <String>[warning.message, warning.recovery]) {
        expect(text, isNot(matches(RegExp(r'\b[A-Z]{2,6}-[0-9]{3}\b'))));
        expect(text, isNot(contains('IMP-')));
        expect(text, isNot(contains('SAVE-')));
        expect(text, isNot(contains('PLT-')));
        expect(text, isNot(contains('/')));
        expect(text, isNot(contains(r'\')));
        expect(text, isNot(contains('content://')));
        expect(text, isNot(contains('file://')));
        expect(text, isNot(contains('.pdf')));
      }
      expect(warning.message, contains('Seiten'));
      expect(warning.recovery, _de.imp006Recovery);
    });

    test('readable pages stay usable in a partial document', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(1, size: _placeholder),
          _readable(2, analysis: PageAnalysisStatus.ready),
        ],
        localizations: _de,
      );

      expect(result.readablePageCount, 2);
      expect(result.unreadablePageCount, 1);
      for (final PageState page in result.pages) {
        if (page.isUnreadable) {
          expect(page.isUsable, isFalse);
          expect(page.displaySize, isNull);
        } else {
          expect(page.isUsable, isTrue);
          expect(page.displaySize, isNotNull);
          expect(page.statusLabel, isNull);
        }
      }
    });

    test('a partial document is not an error state', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(1, size: _placeholder),
        ],
        localizations: _de,
      );

      expect(result, isNot(isA<PageStateFullyUnreadable>()));
      expect(result.isSuccess, isTrue);
      expect(result.isErrorState, isFalse);
    });

    test('derived collections are immutable', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _readable(0),
          _unreadablePage(1, size: _placeholder),
        ],
        localizations: _de,
      );
      final PageStateSuccess success = result as PageStateSuccess;

      expect(() => success.warning!.pageNumbers.add(3), throwsUnsupportedError);
      expect(() => success.pages.clear(), throwsUnsupportedError);
      expect(() => success.unreadablePages.clear(), throwsUnsupportedError);
      expect(
        () => success.unreadablePageNumbers.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('fully unreadable document', () {
    test('all pages unreadable yields the explicit error state', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _unreadablePage(0, size: _placeholder),
          _unreadablePage(1, size: _placeholder),
          _unreadablePage(2, size: _placeholder),
        ],
        localizations: _de,
      );

      expect(result, isA<PageStateFullyUnreadable>());
      expect(result.isSuccess, isFalse);
      expect(result.isErrorState, isTrue);
      expect(result.readablePageCount, 0);
      expect(result.unreadablePageCount, 3);
      expect(result.unreadablePageNumbers, <int>[1, 2, 3]);
    });

    test('a single unreadable page is a fully unreadable document', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[_unreadablePage(0, size: _placeholder)],
        localizations: _de,
      );

      expect(result, isA<PageStateFullyUnreadable>());
      expect(result.isSuccess, isFalse);
      expect(result.pages.single.displaySize, isNull);
    });

    test('the error state exposes no renderable size and no warning', () {
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[
          _unreadablePage(0, size: _placeholder),
          _unreadablePage(1, size: _a4),
        ],
        localizations: _de,
      );

      expect(result, isNot(isA<PageStateSuccess>()));
      for (final PageState page in result.pages) {
        expect(page.isUnreadable, isTrue);
        expect(page.displaySize, isNull);
        expect(page.statusLabel, _de.statusUnreadable);
      }
    });
  });

  group('input validation and privacy', () {
    test('rejects an empty page collection', () {
      expect(
        () => derivePageStates(
          pages: const <PageStateInput>[],
          localizations: _de,
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate page indices', () {
      expect(
        () => derivePageStates(
          pages: <PageStateInput>[_readable(0), _readable(0)],
          localizations: _de,
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-contiguous page indices', () {
      expect(
        () => derivePageStates(
          pages: <PageStateInput>[_readable(0), _readable(2)],
          localizations: _de,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a negative page index at construction', () {
      expect(
        () => PageStateInput(
          index: -1,
          analysis: PageAnalysisStatus.pending,
          reportedDisplaySize: _a4,
        ),
        throwsArgumentError,
      );
    });

    test('requires a failure key exactly for a failed analysis', () {
      expect(
        () => PageStateInput(
          index: 0,
          analysis: PageAnalysisStatus.failed,
          reportedDisplaySize: _a4,
        ),
        throwsArgumentError,
      );
      expect(
        () => PageStateInput(
          index: 0,
          analysis: PageAnalysisStatus.pending,
          failureMessageKey: _imp006,
          reportedDisplaySize: _a4,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a malformed failure key without echoing it', () {
      Object? error;
      try {
        PageStateInput(
          index: 0,
          analysis: PageAnalysisStatus.failed,
          failureMessageKey: 'content://private/document',
          reportedDisplaySize: _a4,
        );
      } on ArgumentError catch (caught) {
        error = caught;
      }
      expect(error, isA<ArgumentError>());
      expect(error.toString(), isNot(contains('content://')));
      expect(error.toString(), isNot(contains('private')));
    });

    test('requires a reported size for a readable page', () {
      expect(
        () => PageStateInput(index: 0, analysis: PageAnalysisStatus.pending),
        throwsArgumentError,
      );
    });

    test('rejects a non-finite, zero, or negative display size', () {
      final List<(double, double)> sizes = <(double, double)>[
        (double.nan, 1),
        (1, double.infinity),
        (0, 1),
        (1, -1),
      ];
      for (final (double width, double height) in sizes) {
        expect(
          () => PageDisplaySize(widthPt: width, heightPt: height),
          throwsArgumentError,
        );
      }
    });

    test('input and state toString omit geometry and content', () {
      final PageStateInput input = _unreadablePage(1, size: _placeholder);
      final PageStateResult result = derivePageStates(
        pages: <PageStateInput>[_readable(0), input],
        localizations: _de,
      );

      for (final String text in <String>[
        input.toString(),
        result.pages[1].toString(),
        (result as PageStateSuccess).warning.toString(),
      ]) {
        expect(text, isNot(contains('1.0pt')));
        expect(text, isNot(contains('595.28')));
        expect(text, isNot(contains('.pdf')));
        expect(text, isNot(contains('/')));
      }
    });
  });

  group('canonical Page compatibility', () {
    test('every core analysis state maps to exactly one phase', () {
      final List<core.Page> persisted = <core.Page>[
        _corePage(index: 0, analysis: core.AnalysisState.pending),
        _corePage(index: 1, analysis: core.AnalysisState.running),
        _corePage(index: 2, analysis: core.AnalysisState.complete),
        _corePage(
          index: 3,
          analysis: core.AnalysisState.failed,
          failure: core.PageFailure(
            pageIndex: 3,
            category: core.PageFailureCategory.rasterization,
            messageKey: 'REC-002',
          ),
        ),
      ];

      final PageStateResult result = derivePageStates(
        pages: persisted.map(_fromCorePage),
        localizations: _de,
      );

      expect(
        result.pages.map((PageState page) => page.analysis),
        <PageAnalysisStatus>[
          PageAnalysisStatus.pending,
          PageAnalysisStatus.analyzing,
          PageAnalysisStatus.ready,
          PageAnalysisStatus.failed,
        ],
      );
      expect(result.pages[3].statusLabel, _de.rec002(4));
      expect(result.isSuccess, isTrue);
    });

    test('a canonical unreadable page keeps its flag and failure key', () {
      final core.Page persisted = _corePage(
        index: 0,
        analysis: core.AnalysisState.failed,
        failure: core.PageFailure(
          pageIndex: 0,
          category: core.PageFailureCategory.unreadable,
          messageKey: _imp006,
        ),
        unreadable: true,
        width: 1,
        height: 1,
      );

      final PageState page = derivePageStates(
        pages: <PageStateInput>[_fromCorePage(persisted)],
        localizations: _de,
      ).pages.single;

      expect(page.isUnreadable, isTrue);
      expect(page.isUsable, isFalse);
      expect(page.displaySize, isNull);
      expect(page.failureMessageKey, _imp006);
      expect(page.statusLabel, _de.statusUnreadable);
    });
  });
}
