// T091 durability label and PRIV-001 disclosure host widget tests.
//
// Evidence class: NONE. These are host-VM widget tests with synthetic hosts
// and the committed German ARB. They build no platform channel, open no
// document, invoke no editor, persistence, file, network, or localization
// service, and make no Android, device, screen-reader, or visual claim.
//
// They prove the pinned T091 behaviour:
//   * all six durability states render the exact ARB label, the pinned icon,
//     and the local 24-hour time where the label carries one;
//   * only clean and saved show a durable check, and unsaved/saveFailed stay
//     distinct by icon and wording;
//   * each state has exactly one status semantic node carrying its visible
//     text, with no duplicate icon or spinner announcement;
//   * a null time renders the visible `--:--` fallback, never a clock read;
//   * the visible PRIV-001 card renders the exact `priv001` sentence, has one
//     semantic node, and offers no dismiss or tap action; the hidden surface
//     reserves no space and exposes no semantics;
//   * 200 % text scale reflows both widgets in a narrow bounded width;
//   * the production source stays presentation-only.

@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/features/editor/durability_status.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/package_root.dart';

/// Narrow bounded width used to force wrapping at 200 % text scale.
const double _narrowWidth = 280;

const String _revisionId = '1b4e28ba-2fa1-4d3b-a1f8-6f2a3c4d5e6f';

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

final DateTime _savedAt = DateTime.utc(2026, 11, 20, 7, 5);

/// One pinned durability case: status, exact text, icon, and durability.
final class _StatusCase {
  const _StatusCase({
    required this.name,
    required this.status,
    required this.text,
    required this.icon,
    this.lastDurableAt,
    this.loading = false,
    this.durableCheck = false,
  });

  final String name;
  final core.DurabilityStatus status;
  final String text;
  final IconData? icon;
  final DateTime? lastDurableAt;
  final bool loading;
  final bool durableCheck;
}

/// The six states with their pinned labels and markers.
List<_StatusCase> _statusCases() {
  final String time = _hhmm(_savedAt);
  return <_StatusCase>[
    _StatusCase(
      name: 'clean',
      status: core.DurabilityStatus.clean,
      text: _de.durabilityClean,
      icon: Icons.check_circle_outline,
      durableCheck: true,
    ),
    _StatusCase(
      name: 'saving',
      status: core.DurabilityStatus.saving,
      text: _de.durabilitySaving,
      icon: null,
      loading: true,
    ),
    _StatusCase(
      name: 'unsaved',
      status: core.DurabilityStatus.unsaved,
      text: _de.durabilityUnsaved,
      icon: Icons.warning_amber_rounded,
    ),
    _StatusCase(
      name: 'saved',
      status: core.DurabilityStatus.saved(lastDurableAt: _savedAt),
      text: _de.durabilitySaved(time),
      icon: Icons.check_circle,
      durableCheck: true,
    ),
    _StatusCase(
      name: 'saveFailed',
      status: core.DurabilityStatus.saveFailed('SAVE-003'),
      text: _de.durabilitySaveFailed(time),
      icon: Icons.error_outline,
      lastDurableAt: _savedAt,
    ),
    _StatusCase(
      name: 'recoveryFallback',
      status: core.DurabilityStatus.recoveryFallback(_revisionId),
      text: _de.durabilityRecoveryFallback,
      icon: Icons.restore,
    ),
  ];
}

Widget _label(_StatusCase statusCase) {
  return DurabilityStatusLabel(
    status: statusCase.status,
    lastDurableAt: statusCase.lastDurableAt,
  );
}

/// Mirrors the pinned local 24-hour formatting rule for expected values.
String _hhmm(DateTime time) {
  final DateTime local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

Widget _host(
  Widget child, {
  double textScale = 1.0,
  double width = _narrowWidth,
}) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext context, Widget? child) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );
    },
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

Iterable<SemanticsNode> _traversal(WidgetTester tester) {
  return tester.semantics.simulatedAccessibilityTraversal();
}

/// Labels that an assistive technology would announce, in traversal order.
List<String> _visibleLabels(WidgetTester tester) {
  return _traversal(tester)
      .map((SemanticsNode node) => node.getSemanticsData().label)
      .where((String label) => label.isNotEmpty)
      .toList();
}

void main() {
  testWidgets(
    'every durability state renders its exact ARB label and pinned icon',
    (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      for (final _StatusCase statusCase in _statusCases()) {
        await tester.pumpWidget(_host(_label(statusCase)));
        await tester.pump();

        expect(tester.takeException(), isNull, reason: statusCase.name);
        expect(
          find.text(statusCase.text),
          findsOneWidget,
          reason: statusCase.name,
        );

        if (statusCase.loading) {
          expect(
            find.descendant(
              of: find.byKey(durabilityStatusLabelKey),
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
            reason: statusCase.name,
          );
          expect(
            find.descendant(
              of: find.byKey(durabilityStatusLabelKey),
              matching: find.byType(Icon),
            ),
            findsNothing,
            reason: '${statusCase.name} must not add a check icon',
          );
        } else {
          expect(
            find.descendant(
              of: find.byKey(durabilityStatusLabelKey),
              matching: find.byType(CircularProgressIndicator),
            ),
            findsNothing,
            reason: statusCase.name,
          );
          expect(
            find.descendant(
              of: find.byKey(durabilityStatusLabelKey),
              matching: find.byIcon(statusCase.icon!),
            ),
            findsOneWidget,
            reason: statusCase.name,
          );
        }
      }

      handle.dispose();
    },
  );

  testWidgets(
    'saved and saveFailed render local 24-hour time from explicit or saved UTC',
    (WidgetTester tester) async {
      final DateTime explicitTime = DateTime.utc(2026, 11, 20, 15, 4);
      final String statusTimeLabel = _hhmm(_savedAt);
      final String explicitTimeLabel = _hhmm(explicitTime);

      expect(statusTimeLabel, matches(RegExp(r'^\d{2}:\d{2}$')));
      expect(explicitTimeLabel, matches(RegExp(r'^\d{2}:\d{2}$')));

      await tester.pumpWidget(
        _host(
          DurabilityStatusLabel(
            status: core.DurabilityStatus.saved(lastDurableAt: _savedAt),
          ),
        ),
      );
      expect(find.text(_de.durabilitySaved(statusTimeLabel)), findsOneWidget);
      expect(
        _de.durabilitySaved(statusTimeLabel),
        _de.durabilitySaved(_hhmm(_savedAt)),
      );

      await tester.pumpWidget(
        _host(
          DurabilityStatusLabel(
            status: core.DurabilityStatus.saved(lastDurableAt: _savedAt),
            lastDurableAt: explicitTime,
          ),
        ),
      );
      expect(find.text(_de.durabilitySaved(explicitTimeLabel)), findsOneWidget);
      expect(find.text(_de.durabilitySaved(statusTimeLabel)), findsNothing);

      await tester.pumpWidget(
        _host(
          DurabilityStatusLabel(
            status: core.DurabilityStatus.saveFailed('SAVE-001'),
            lastDurableAt: explicitTime,
          ),
        ),
      );
      expect(
        find.text(_de.durabilitySaveFailed(explicitTimeLabel)),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    },
  );

  test(
    'time label is local, 24-hour, zero-padded, and never reads a clock',
    () {
      expect(durabilityTimeLabel(DateTime(2026, 1, 1, 8, 5)), '08:05');
      expect(durabilityTimeLabel(DateTime(2026, 1, 1, 23, 59)), '23:59');
      expect(
        durabilityTimeLabel(DateTime.utc(2026, 1, 1, 0, 0)),
        _hhmm(DateTime.utc(2026, 1, 1, 0, 0)),
      );
      expect(durabilityTimeLabel(null), '--:--');
    },
  );

  testWidgets(
    'null time renders the exact --:-- fallback for saved and saveFailed',
    (WidgetTester tester) async {
      // SavedDurabilityStatus always carries a UTC time, so the shared formatter
      // is the only way that state can reach the fallback. Both ARB compositions
      // and the saveFailed widget boundary use the same visible literal.
      expect(durabilityTimeLabel(null), '--:--');
      expect(_de.durabilitySaved('--:--'), 'Gespeichert um --:--');
      expect(
        _de.durabilitySaveFailed('--:--'),
        'Speichern fehlgeschlagen – letzter gespeicherter Stand: --:--',
      );

      await tester.pumpWidget(
        _host(
          DurabilityStatusLabel(
            status: core.DurabilityStatus.saveFailed('SAVE-003'),
          ),
        ),
      );
      expect(find.text(_de.durabilitySaveFailed('--:--')), findsOneWidget);
      expect(find.textContaining('--:--'), findsOneWidget);
    },
  );

  testWidgets('only clean and saved may show a durable check', (
    WidgetTester tester,
  ) async {
    const List<IconData> checks = <IconData>[
      Icons.check,
      Icons.check_circle,
      Icons.check_circle_outline,
    ];

    for (final _StatusCase statusCase in _statusCases()) {
      await tester.pumpWidget(_host(_label(statusCase)));
      await tester.pump();

      final bool hasCheck = checks.any(
        (IconData icon) => find
            .descendant(
              of: find.byKey(durabilityStatusLabelKey),
              matching: find.byIcon(icon),
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(
        hasCheck,
        statusCase.durableCheck,
        reason: '${statusCase.name} check presentation',
      );
    }

    await tester.pumpWidget(
      _host(DurabilityStatusLabel(status: core.DurabilityStatus.unsaved)),
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text(_de.durabilityUnsaved), findsOneWidget);

    await tester.pumpWidget(
      _host(
        DurabilityStatusLabel(
          status: core.DurabilityStatus.saveFailed('SAVE-003'),
        ),
      ),
    );
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text(_de.durabilitySaveFailed(_hhmm(_savedAt))), findsNothing);
    expect(find.text(_de.durabilitySaveFailed('--:--')), findsOneWidget);
    expect(Icons.warning_amber_rounded, isNot(Icons.error_outline));
  });

  testWidgets('one status semantic node carries the exact visible text', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();

    for (final _StatusCase statusCase in _statusCases()) {
      await tester.pumpWidget(_host(_label(statusCase)));
      await tester.pump();

      final SemanticsNode node = tester.getSemantics(
        find.byKey(durabilityStatusLabelKey),
      );
      final SemanticsData data = node.getSemanticsData();
      expect(data.label, statusCase.text, reason: statusCase.name);
      expect(data.role, SemanticsRole.status, reason: statusCase.name);

      final Iterable<SemanticsNode> matching = _traversal(tester).where(
        (SemanticsNode candidate) =>
            candidate.getSemanticsData().label.contains(statusCase.text),
      );
      expect(matching, hasLength(1), reason: statusCase.name);
      expect(matching.single.id, node.id, reason: statusCase.name);
      expect(_visibleLabels(tester), <String>[
        statusCase.text,
      ], reason: '${statusCase.name} must not announce its icon or spinner');
    }

    handle.dispose();
  });

  testWidgets('stable keys identify the status surface and disclosure', (
    WidgetTester tester,
  ) async {
    expect(
      durabilityStatusLabelKey,
      const ValueKey<String>('durability-status-label'),
    );
    expect(
      privacyKeyDisclosureKey,
      const ValueKey<String>('privacy-key-disclosure'),
    );

    await tester.pumpWidget(
      _host(DurabilityStatusLabel(status: core.DurabilityStatus.clean)),
    );
    expect(
      find.byKey(const ValueKey<String>('durability-status-label')),
      findsOneWidget,
    );

    await tester.pumpWidget(_host(const PrivacyKeyDisclosure()));
    expect(
      find.byKey(const ValueKey<String>('privacy-key-disclosure')),
      findsOneWidget,
    );
  });

  testWidgets(
    'visible PRIV-001 disclosure renders the exact sentence and one node',
    (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(_host(const PrivacyKeyDisclosure()));

      expect(find.byKey(privacyKeyDisclosureKey), findsOneWidget);
      expect(find.text(_de.priv001), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      final Text text = tester.widget<Text>(find.text(_de.priv001));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);

      final SemanticsNode node = tester.getSemantics(
        find.byKey(privacyKeyDisclosureKey),
      );
      final SemanticsData data = node.getSemanticsData();
      expect(data.label, _de.priv001);
      expect(data.hasAction(SemanticsAction.dismiss), isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      final Iterable<SemanticsNode> matching = _traversal(tester).where(
        (SemanticsNode candidate) =>
            candidate.getSemanticsData().label.contains(_de.priv001),
      );
      expect(matching, hasLength(1));
      expect(matching.single.id, node.id);
      expect(_visibleLabels(tester), <String>[_de.priv001]);

      // No dismiss or retry control exists; only the caller's rebuild hides it.
      expect(
        find.descendant(
          of: find.byType(PrivacyKeyDisclosure),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(PrivacyKeyDisclosure),
          matching: find.byType(Dismissible),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(PrivacyKeyDisclosure),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      for (final IconData control in <IconData>[
        Icons.close,
        Icons.cancel,
        Icons.refresh,
        Icons.replay,
      ]) {
        expect(
          find.descendant(
            of: find.byType(PrivacyKeyDisclosure),
            matching: find.byIcon(control),
          ),
          findsNothing,
        );
      }

      handle.dispose();
    },
  );

  testWidgets(
    'hidden PRIV-001 disclosure reserves no space and exposes no semantics',
    (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(_host(const PrivacyKeyDisclosure()));
      expect(find.byKey(privacyKeyDisclosureKey), findsOneWidget);

      await tester.pumpWidget(
        _host(const PrivacyKeyDisclosure(visible: false)),
      );

      expect(tester.getSize(find.byType(PrivacyKeyDisclosure)).height, 0);
      expect(find.byKey(privacyKeyDisclosureKey), findsNothing);
      expect(find.text(_de.priv001), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.bySemanticsLabel(_de.priv001), findsNothing);
      expect(
        _traversal(tester).where(
          (SemanticsNode node) =>
              node.getSemanticsData().label.contains(_de.priv001),
        ),
        isEmpty,
      );
      expect(_visibleLabels(tester), isEmpty);

      handle.dispose();
    },
  );

  testWidgets('200 percent scale reflows every status in a narrow width', (
    WidgetTester tester,
  ) async {
    for (final _StatusCase statusCase in _statusCases()) {
      await tester.pumpWidget(_host(_label(statusCase), textScale: 2.0));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: statusCase.name);
      expect(
        find.text(statusCase.text),
        findsOneWidget,
        reason: statusCase.name,
      );

      final Rect rect = tester.getRect(find.byKey(durabilityStatusLabelKey));
      expect(rect.width, lessThanOrEqualTo(_narrowWidth));
      expect(
        tester.getSize(find.byKey(durabilityStatusLabelKey)).height,
        greaterThan(0),
        reason: statusCase.name,
      );

      final Text text = tester.widget<Text>(find.text(statusCase.text));
      expect(text.maxLines, isNull, reason: statusCase.name);
      expect(text.overflow, isNull, reason: statusCase.name);
    }
  });

  testWidgets(
    '200 percent scale reflows the PRIV-001 disclosure in a narrow width',
    (WidgetTester tester) async {
      await tester.pumpWidget(_host(const PrivacyKeyDisclosure()));
      final double regularHeight = tester
          .getSize(find.byKey(privacyKeyDisclosureKey))
          .height;
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _host(const PrivacyKeyDisclosure(), textScale: 2.0),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_de.priv001), findsOneWidget);

      final Rect rect = tester.getRect(find.byKey(privacyKeyDisclosureKey));
      expect(rect.width, lessThanOrEqualTo(_narrowWidth));
      expect(
        tester.getSize(find.byKey(privacyKeyDisclosureKey)).height,
        greaterThan(regularHeight),
      );

      final Text text = tester.widget<Text>(find.text(_de.priv001));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
    },
  );

  test('production source stays presentation-only', () {
    final File file = File(
      '${packageRoot.path}/lib/features/editor/durability_status.dart',
    );
    expect(file.existsSync(), isTrue);

    final String source = file.readAsStringSync();
    final List<String> imports = RegExp(
      r"^import '([^']+)';",
      multiLine: true,
    ).allMatches(source).map((Match match) => match.group(1)!).toList();

    expect(imports, <String>[
      'package:feldexa_app/l10n/app_localizations.dart',
      'package:feldexa_core/feldexa_core.dart',
      'package:flutter/material.dart',
      'package:flutter/semantics.dart',
    ]);
    for (final String getter in <String>[
      'l10n.durabilityClean',
      'l10n.durabilitySaving',
      'l10n.durabilitySaved',
      'l10n.durabilityUnsaved',
      'l10n.durabilitySaveFailed',
      'l10n.durabilityRecoveryFallback',
      'l10n.priv001',
    ]) {
      expect(source, contains(getter));
    }
    for (final String forbidden in <String>[
      'dart:io',
      'dart:html',
      'dart:convert',
      'package:http',
      'HttpClient',
      'shared_preferences',
      'sqflite',
      'database',
      'Database',
      'File(',
      'Directory(',
      'path_provider',
      'readAsString',
      'writeAsString',
      'dart:developer',
      'debugPrint',
      'logging',
      'Logger',
      'AutosaveCoordinator',
      'autosave',
      'Autosave',
      'SaveCoordinator',
      'EditorScreen',
      'editor_screen',
      'feldexa_application',
      'feldexa_ports',
    ]) {
      expect(
        source,
        isNot(contains(forbidden)),
        reason: 'The presentation surface must not reference $forbidden.',
      );
    }
    expect(
      RegExp(r'DateTime\s*\.\s*now\s*\(').hasMatch(source),
      isFalse,
      reason: 'The label must never read the wall clock.',
    );
  });
}
