// T096 start-list deletion confirmation host widget tests.
//
// Evidence class: NONE. These are host-VM widget tests with the committed
// German ARB. They build no platform channel, open no store, and make no
// Android, device, screen-reader, or visual claim.
//
// They prove the pinned T096 behaviour:
//   * the document and template dialogs render only their exact existing ARB
//     sentence, with the title inserted exactly once;
//   * confirm returns true exactly once, while cancel and barrier dismissal
//     return false exactly once;
//   * no callback, store, route, snackbar, or deletion side effect occurs; the
//     observer sees only the dialog route push and pop;
//   * the stable dialog and action keys exist;
//   * `deletionConfirmationMessage` returns exactly the ARB sentence;
//   * 200 % text scale reflows at 280 logical pixels without overflow;
//   * the production source is ASCII, contains no German literal, references
//     only the three authorized ARB getters, and has only the two authorized
//     imports.

@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/features/start/delete_item.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _documentTitle = 'Antrag 2026';
const String _templateTitle = 'Vorlage Standard';

const ValueKey<String> _dialogKey = ValueKey<String>('delete-item-dialog');
const ValueKey<String> _confirmKey = ValueKey<String>('delete-item-confirm');
const ValueKey<String> _cancelKey = ValueKey<String>('delete-item-cancel');
const ValueKey<String> _homeKey = ValueKey<String>('delete-item-host');
const ValueKey<String> _documentButtonKey = ValueKey<String>(
  'delete-item-open-document',
);
const ValueKey<String> _templateButtonKey = ValueKey<String>(
  'delete-item-open-template',
);

final AppLocalizations _de = lookupAppLocalizations(const Locale('de'));

String _expectedMessage(DeleteItemKind kind, String title) {
  return switch (kind) {
    DeleteItemKind.document => _de.deleteDocumentDialog(title),
    DeleteItemKind.template => _de.deleteTemplateDialog(title),
  };
}

/// One dialog case: its opener, its kind, and its title.
typedef _Case = ({ValueKey<String> button, DeleteItemKind kind, String title});

final List<_Case> _cases = <_Case>[
  (
    button: _documentButtonKey,
    kind: DeleteItemKind.document,
    title: _documentTitle,
  ),
  (
    button: _templateButtonKey,
    kind: DeleteItemKind.template,
    title: _templateTitle,
  ),
];

/// Test-side host that records the returned choice exactly once.
///
/// The production API takes no callback, so the test supplies none: the host
/// merely awaits the returned bool and appends it to [results].
class _Host extends StatelessWidget {
  const _Host({required this.results});

  final List<bool> results;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _homeKey,
      body: Column(
        children: <Widget>[
          TextButton(
            key: _documentButtonKey,
            onPressed: () async {
              final bool confirmed = await showDeleteItemConfirmation(
                context,
                kind: DeleteItemKind.document,
                title: _documentTitle,
              );
              results.add(confirmed);
            },
            child: const Text('open document'),
          ),
          TextButton(
            key: _templateButtonKey,
            onPressed: () async {
              final bool confirmed = await showDeleteItemConfirmation(
                context,
                kind: DeleteItemKind.template,
                title: _templateTitle,
              );
              results.add(confirmed);
            },
            child: const Text('open template'),
          ),
        ],
      ),
    );
  }
}

Widget _app({
  required List<bool> results,
  NavigatorObserver? observer,
  double textScale = 1.0,
}) {
  return MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: <NavigatorObserver>[?observer],
    builder: (BuildContext context, Widget? child) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );
    },
    home: _Host(results: results),
  );
}

Future<void> _openDialog(WidgetTester tester, ValueKey<String> button) async {
  await tester.tap(find.byKey(button));
  await tester.pumpAndSettle();
}

/// One recorded navigator transition.
final class _RouteEvent {
  const _RouteEvent({
    required this.action,
    required this.name,
    required this.isDialog,
  });

  final String action;
  final String? name;
  final bool isDialog;
}

/// Records navigator transitions after the host is already mounted.
final class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<_RouteEvent> events = <_RouteEvent>[];

  void _record(String action, Route<dynamic>? route) {
    if (route == null) {
      return;
    }
    events.add(
      _RouteEvent(
        action: action,
        name: route.settings.name,
        isDialog: route is DialogRoute<dynamic>,
      ),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('push', route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('pop', route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('remove', route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _record('replace', newRoute ?? oldRoute);
  }
}

void _expectOnlyDialogRoute(_RecordingNavigatorObserver observer) {
  expect(observer.events, hasLength(2));
  expect(observer.events[0].action, 'push');
  expect(observer.events[0].isDialog, isTrue);
  expect(observer.events[0].name, isNull);
  expect(observer.events[1].action, 'pop');
  expect(observer.events[1].isDialog, isTrue);
  expect(observer.events[1].name, isNull);
}

void main() {
  group('exact ARB content', () {
    testWidgets('document kind shows only the exact DEL-002 message', (
      WidgetTester tester,
    ) async {
      final List<bool> results = <bool>[];
      await tester.pumpWidget(_app(results: results));
      await _openDialog(tester, _documentButtonKey);

      final String expected = _de.deleteDocumentDialog(_documentTitle);
      final AlertDialog dialog = tester.widget<AlertDialog>(
        find.byKey(_dialogKey),
      );

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(dialog.title, isNull);
      expect(dialog.content, isA<Text>());
      expect((dialog.content! as Text).data, expected);
      expect(find.text(expected), findsOneWidget);
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .where((Text text) => text.data == expected),
        hasLength(1),
      );
      expect(
        expected,
        contains('Andere Dokumente und Vorlagen bleiben erhalten.'),
      );
      expect(
        expected,
        isNot(
          contains(
            'Dokumente, die aus dieser Vorlage erstellt wurden, bleiben '
            'unverändert und weiterhin nutzbar.',
          ),
        ),
      );
      expect(find.text(_de.deleteTemplateDialog(_documentTitle)), findsNothing);
      expect(find.text(_de.deletionConfirmation(_documentTitle)), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
    });

    testWidgets('template kind shows only the exact DEL-003 message', (
      WidgetTester tester,
    ) async {
      final List<bool> results = <bool>[];
      await tester.pumpWidget(_app(results: results));
      await _openDialog(tester, _templateButtonKey);

      final String expected = _de.deleteTemplateDialog(_templateTitle);
      final AlertDialog dialog = tester.widget<AlertDialog>(
        find.byKey(_dialogKey),
      );

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(dialog.title, isNull);
      expect(dialog.content, isA<Text>());
      expect((dialog.content! as Text).data, expected);
      expect(find.text(expected), findsOneWidget);
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .where((Text text) => text.data == expected),
        hasLength(1),
      );
      expect(
        expected,
        contains(
          'Dokumente, die aus dieser Vorlage erstellt wurden, bleiben '
          'unverändert und weiterhin nutzbar.',
        ),
      );
      expect(
        expected,
        isNot(contains('Andere Dokumente und Vorlagen bleiben erhalten.')),
      );
      expect(find.text(_de.deleteDocumentDialog(_templateTitle)), findsNothing);
      expect(find.text(_de.deletionConfirmation(_templateTitle)), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
    });
  });

  group('result semantics', () {
    testWidgets('confirm returns true exactly once', (
      WidgetTester tester,
    ) async {
      final List<bool> results = <bool>[];
      await tester.pumpWidget(_app(results: results));
      await _openDialog(tester, _documentButtonKey);

      await tester.tap(find.byKey(_confirmKey));
      await tester.pumpAndSettle();
      await tester.pump();

      expect(results, <bool>[true]);
      expect(find.byKey(_dialogKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancel returns false exactly once', (
      WidgetTester tester,
    ) async {
      final List<bool> results = <bool>[];
      await tester.pumpWidget(_app(results: results));
      await _openDialog(tester, _templateButtonKey);

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
      await tester.pump();

      expect(results, <bool>[false]);
      expect(find.byKey(_dialogKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('barrier dismissal returns false exactly once', (
      WidgetTester tester,
    ) async {
      final List<bool> results = <bool>[];
      await tester.pumpWidget(_app(results: results));
      await _openDialog(tester, _documentButtonKey);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      await tester.pump();

      expect(results, <bool>[false]);
      expect(find.byKey(_dialogKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'confirm, cancel, and barrier keep the host and move only the dialog route',
    (WidgetTester tester) async {
      final List<bool> results = <bool>[];
      final _RecordingNavigatorObserver observer =
          _RecordingNavigatorObserver();
      await tester.pumpWidget(_app(results: results, observer: observer));

      Future<void> check({
        required String label,
        required ValueKey<String> button,
        required Future<void> Function() close,
        required bool expected,
      }) async {
        observer.events.clear();
        await _openDialog(tester, button);
        expect(find.byKey(_dialogKey), findsOneWidget, reason: label);

        await close();
        expect(results, <bool>[expected], reason: label);
        expect(find.byKey(_homeKey), findsOneWidget, reason: label);
        expect(find.byKey(_dialogKey), findsNothing, reason: label);
        expect(find.byType(SnackBar), findsNothing, reason: label);
        _expectOnlyDialogRoute(observer);
        results.clear();
      }

      await check(
        label: 'confirm',
        button: _documentButtonKey,
        close: () async {
          await tester.tap(find.byKey(_confirmKey));
          await tester.pumpAndSettle();
        },
        expected: true,
      );

      await check(
        label: 'cancel',
        button: _templateButtonKey,
        close: () async {
          await tester.tap(find.byKey(_cancelKey));
          await tester.pumpAndSettle();
        },
        expected: false,
      );

      await check(
        label: 'barrier',
        button: _documentButtonKey,
        close: () async {
          await tester.tapAt(const Offset(8, 8));
          await tester.pumpAndSettle();
        },
        expected: false,
      );

      expect(find.byKey(_homeKey), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the title appears exactly once and the stable keys identify all controls',
    (WidgetTester tester) async {
      final List<bool> results = <bool>[];
      await tester.pumpWidget(_app(results: results));

      for (final _Case entry in _cases) {
        await _openDialog(tester, entry.button);

        final AlertDialog dialog = tester.widget<AlertDialog>(
          find.byKey(_dialogKey),
        );
        final Text content = dialog.content! as Text;
        final String text = content.data!;

        expect(text.split(entry.title).length - 1, 1, reason: entry.title);
        for (final Text widget in tester.widgetList<Text>(find.byType(Text))) {
          expect(widget.data, isNot(entry.title), reason: entry.title);
        }
        expect(tester.widget(find.byKey(_dialogKey)), isA<AlertDialog>());
        expect(tester.widget(find.byKey(_confirmKey)), isA<TextButton>());
        expect(tester.widget(find.byKey(_cancelKey)), isA<TextButton>());

        await tester.tap(find.byKey(_cancelKey));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  test('deletionConfirmationMessage returns the exact ARB sentence', () {
    for (final String title in <String>[
      _documentTitle,
      _templateTitle,
      'Ein weiterer Antrag',
    ]) {
      final String message = deletionConfirmationMessage(_de, title);
      final String expected = _de.deletionConfirmation(title);

      expect(message, expected);
      expect(message, equals(expected));
      expect(message, message.trim());
      expect(message, isNot(contains('  ')));
    }
  });

  testWidgets(
    '200 % text scale reflows at 280 logical pixels without overflow',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(280, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final List<bool> results = <bool>[];
      await tester.pumpWidget(_app(results: results, textScale: 2.0));

      for (final _Case entry in _cases) {
        await _openDialog(tester, entry.button);

        expect(tester.takeException(), isNull, reason: entry.title);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byKey(_dialogKey), findsOneWidget);
        expect(find.byKey(_confirmKey), findsOneWidget);
        expect(find.byKey(_cancelKey), findsOneWidget);

        final AlertDialog dialog = tester.widget<AlertDialog>(
          find.byKey(_dialogKey),
        );
        expect(
          (dialog.content! as Text).data,
          _expectedMessage(entry.kind, entry.title),
          reason: entry.title,
        );

        if (entry.kind == DeleteItemKind.document) {
          await tester.tap(find.byKey(_cancelKey));
        } else {
          await tester.tap(find.byKey(_confirmKey));
        }
        await tester.pumpAndSettle();
        expect(results, <bool>[
          entry.kind == DeleteItemKind.document ? false : true,
        ]);
        results.clear();
        expect(find.byKey(_dialogKey), findsNothing);
        expect(tester.takeException(), isNull, reason: entry.title);
      }
    },
  );

  test('production source is ASCII, German-free, and presentation-only', () {
    final File file = File('lib/features/start/delete_item.dart');
    expect(file.existsSync(), isTrue);

    final String source = file.readAsStringSync();

    expect(
      source.codeUnits.every((int unit) => unit < 128),
      isTrue,
      reason: 'The production source must stay pure ASCII.',
    );
    for (final String german in <String>[
      'Möchten',
      'gelöscht',
      'Vorlage',
      'Dokumente',
      'Andere',
    ]) {
      expect(
        source,
        isNot(contains(german)),
        reason: 'The production source must not contain the German literal.',
      );
    }
    for (final String forbidden in <String>[
      'SecureStorePort',
      'store.',
      'store.list',
      'store.save',
      'showSnackBar',
      'ScaffoldMessenger',
      'Navigator.push',
      'pushNamed',
      'pushReplacement',
      'MaterialPageRoute',
      'DateTime.now',
      'dart:io',
      'package:http',
      'SharedPreferences',
      'sqflite',
    ]) {
      expect(
        source,
        isNot(contains(forbidden)),
        reason: 'The presentation surface must not reference $forbidden.',
      );
    }
    for (final String getter in <String>[
      'l10n.deleteDocumentDialog',
      'l10n.deleteTemplateDialog',
      'l10n.deletionConfirmation',
    ]) {
      expect(source, contains(getter));
    }

    final List<String> imports = RegExp(
      r"^import '([^']+)';",
      multiLine: true,
    ).allMatches(source).map((Match match) => match.group(1)!).toList();
    expect(imports, <String>[
      'package:flutter/material.dart',
      '../../l10n/app_localizations.dart',
    ]);
  });
}
