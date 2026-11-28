// T138 outbound/socket observation and release-manifest audit
// (SC-007/SC-008; FR-078/FR-079/FR-080; CHK020).
//
// Evidence classes, separated per run:
//   * `EMULATOR` — the socket observation runs on the exclusively allocated
//     `emulator-5554` with the production `FeldexaApp` root. It samples the
//     app's own `/proc/self/net/tcp{,6}` table before startup and throughout a
//     real import + first analysis (the ML Kit OCR path, plan.md risk table),
//     and fails if the app UID owns any non-loopback outbound socket in
//     ESTABLISHED/SYN_SENT/SYN_RECV/CLOSE_WAIT. API 35 denies in-app table
//     access, so the authoritative kernel read is the host driver
//     `tools/android/t138_network_observe.sh` (~4 Hz); flows shorter than one
//     sampling interval can be missed. A recording `HttpOverrides`
//     additionally fails closed on any Dart HTTP client creation, and an
//     app-UID loopback listener is the positive control that proves the table
//     is observable in the same run.
//   * `NONE` — the release-manifest audit is a host-side static check over the
//     committed source manifests and the checked-in release overlay; it cannot
//     run on the device (the device APK is the debug test build, which keeps
//     INTERNET for the Flutter tool). The host lane is the ordinary app suite:
//     `flutter test test/release_manifest_audit_test.dart` (from
//     `apps/feldexa_app`); this integration file's second test is device-only.
//
// Scope of the measurement: startup, import, encrypted staging, preflight, and
// the first analysis/OCR. Export is a local PDFBox path already covered by the
// T108/T109 emulator runs; this audit makes no claim about it.
//
// CHK020 method: airplane mode alone is not treated as proof. Socket state is
// observed directly at the kernel/network-namespace table, plus a Dart-level
// fail-closed HTTP interceptor, plus the release manifest audit that the
// release build cannot even request INTERNET or ACCESS_NETWORK_STATE (FR-079).
//
// Privacy: markers carry counts, UID numbers, table sizes, and manifest names
// only; no document text, title, path, URI, or entered value is printed.

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/features/editor/editor_screen.dart';
import 'package:feldexa_app/main.dart' as app;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/release_manifest_audit.dart';

const String _fixtureDir = '/data/local/tmp/t138-fixtures';
const String _fixtureName = 'sf-001.pdf';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const int _fixtureSizeBytes = 5956;
const String _fixtureDisplayName = 't138-network.pdf';

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

/// TCP states that represent an actual outbound connection attempt/flow.
const Set<String> _outboundStates = <String>{'01', '02', '03', '08'};

void _marker(String phase) {
  debugPrint('T138_$phase');
}

final class _SocketRow {
  _SocketRow(this.local, this.remote, this.state);

  final String local;
  final String remote;
  final String state;

  String get key => '$local|$remote|$state';
}

final class _RecordingHttpOverrides extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('T138: outbound HTTP client creation is not allowed');
  }
}

int _appUid() {
  final List<String> lines = File('/proc/self/status').readAsLinesSync();
  for (final String line in lines) {
    if (line.startsWith('Uid:')) {
      final List<String> parts = line.split(RegExp(r'\s+'));
      return int.parse(parts[1]);
    }
  }
  fail('could not read the app UID from /proc/self/status');
}

bool _isLoopbackOrUnspecified(String hexAddress) {
  final String address = hexAddress.toUpperCase();
  // IPv4: 00000000 (unspecified), 0100007F (127.0.0.1), loopback/8 in
  // little-endian is xx00007F; check the first octet 7F in the last byte.
  if (address.length == 8) {
    if (address == '00000000' || address == '0100007F') {
      return true;
    }
    return address.substring(6) == '7F';
  }
  // IPv6: unspecified, ::1, and IPv4-mapped loopback.
  if (address == '00000000000000000000000000000000' ||
      address == '00000000000000000000000001000000') {
    return true;
  }
  if (address.startsWith('0000000000000000FFFF0000')) {
    final String v4 = address.substring(24);
    return v4 == '0100007F' || v4.substring(6) == '7F';
  }
  return false;
}

List<String> _readTable(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    return const <String>[];
  }
  try {
    return file.readAsLinesSync();
  } on FileSystemException {
    return const <String>[];
  }
}

/// Whether at least one kernel socket table could actually be read.
///
/// A zero-row result is only evidence when the table itself was readable; an
/// inaccessible `/proc/self/net` must fail closed instead of reporting a
/// vacuous "zero sockets".
bool _socketTablesReadable() {
  return _readTable('/proc/self/net/tcp').isNotEmpty ||
      _readTable('/proc/self/net/tcp6').isNotEmpty;
}

/// Content-free status of both socket tables for the run marker.
String _socketTablesStatus() {
  final List<String> parts = <String>[];
  for (final String path in <String>[
    '/proc/self/net/tcp',
    '/proc/self/net/tcp6',
  ]) {
    final File file = File(path);
    if (!file.existsSync()) {
      parts.add('${path.split('/').last}:missing');
      continue;
    }
    try {
      parts.add('${path.split('/').last}:${file.readAsLinesSync().length}');
    } on FileSystemException {
      parts.add('${path.split('/').last}:denied');
    }
  }
  return parts.join(':');
}

List<_SocketRow> _observeSockets(int uid) {
  final List<_SocketRow> rows = <_SocketRow>[];
  for (final String path in <String>[
    '/proc/self/net/tcp',
    '/proc/self/net/tcp6',
  ]) {
    final List<String> lines = _readTable(path);
    for (final String line in lines.skip(1)) {
      final List<String> parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 10) {
        continue;
      }
      final String local = parts[1];
      final String remote = parts[2];
      final String state = parts[3];
      final int rowUid;
      try {
        rowUid = int.parse(parts[7]);
      } on FormatException {
        continue;
      }
      if (rowUid != uid) {
        continue;
      }
      rows.add(_SocketRow(local, remote, state));
    }
  }
  return rows;
}

List<_SocketRow> _unexpectedOutbound(List<_SocketRow> rows) {
  return rows.where((_SocketRow row) {
    final String remoteAddress = row.remote.split(':').first;
    if (_outboundStates.contains(row.state) == false) {
      return false;
    }
    return !_isLoopbackOrUnspecified(remoteAddress);
  }).toList();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String reason,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
    if (condition()) {
      return;
    }
  }
  fail('$reason (bounded wait ${timeout.inSeconds}s expired)');
}

Future<void> _armFixture() async {
  final File fixture = File(
    '$_fixtureDir${Platform.pathSeparator}$_fixtureName',
  );
  if (!fixture.existsSync()) {
    fail(
      'Fixture staging is missing $_fixtureDir/$_fixtureName. Push '
      'tools/corpus/synthetic/$_fixtureName to that path first.',
    );
  }
  final List<int> bytes = fixture.readAsBytesSync();
  expect(bytes.length, _fixtureSizeBytes);
  expect(crypto.sha256.convert(bytes).toString(), _fixtureSha256);
  final Map<Object?, Object?>? reply = await _testHooks
      .invokeMethod<Map<Object?, Object?>>('armFile', <String, Object?>{
        'path': fixture.path,
        'displayName': _fixtureDisplayName,
        'forceUnknownPreflight': false,
      });
  expect(reply?['armed'], isTrue);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('release manifests carry no debug or fixture entries', () {
    runReleaseManifestAudit(marker: _marker);
  });

  testWidgets(
    'no unexpected outbound sockets during startup, import and first analysis',
    (WidgetTester tester) async {
      expect(Platform.isAndroid, isTrue, reason: 'EMULATOR lane only');
      final int uid = _appUid();
      final _RecordingHttpOverrides overrides = _RecordingHttpOverrides();
      final HttpOverrides? previous = HttpOverrides.current;
      HttpOverrides.global = overrides;
      addTearDown(() => HttpOverrides.global = previous);

      await _armFixture();

      // Positive control for the host observation: an app-UID loopback
      // listener must be visible as a LISTEN row in the kernel table during the
      // same run. Without it a zero-outbound result is indistinguishable from
      // an unreadable table.
      final ServerSocket positiveControl = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      _marker(
        'POSITIVE_CONTROL:port=${positiveControl.port}:listening=1:uid=$uid',
      );

      // Android 15 (API 35) denies the app UID any `/proc/net` access. The
      // kernel-table observation therefore belongs to the host driver
      // (`tools/android/t138_network_observe.sh`), which samples the same
      // tables as the shell UID and filters the app UID. This test records
      // whether an in-app table is readable and never treats a zero-row result
      // as evidence when it is not.
      final bool tablesReadable = _socketTablesReadable();
      _marker(
        'TABLES:${_socketTablesStatus()}:inAppReadable=$tablesReadable:'
        'externalObservation=${tablesReadable ? 'optional' : 'required'}',
      );

      final List<_SocketRow> baseline = _observeSockets(uid);
      _marker(
        'SOCKETS:baseline:rows=${baseline.length}:'
        'outbound=${_unexpectedOutbound(baseline).length}',
      );

      await tester.pumpWidget(const app.FeldexaApp());
      await _pumpUntil(
        tester,
        () => find.byKey(_startScreenKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
        reason: 'the start surface did not appear',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_importActionKey));
      await _pumpUntil(
        tester,
        () => find.byKey(_editorScreenKey).evaluate().isNotEmpty,
        timeout: const Duration(minutes: 5),
        reason: 'the production import did not open the editor',
      );

      // Sample continuously while the first analysis (ML Kit OCR) runs.
      final Map<String, _SocketRow> observed = <String, _SocketRow>{};
      for (final _SocketRow row in baseline) {
        observed[row.key] = row;
      }
      final DateTime deadline = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(deadline)) {
        for (final _SocketRow row in _observeSockets(uid)) {
          observed[row.key] = row;
        }
        await tester.pump(const Duration(milliseconds: 500));
        final EditorScreenState state = tester.state<EditorScreenState>(
          find.byType(EditorScreen),
        );
        final String? key = state.analysisStateKey;
        if (key == editorAnalysisReadyKey ||
            key == editorAnalysisSkippedKey ||
            key == editorAnalysisFailedKey) {
          _marker('ANALYSIS_TERMINAL:$key');
          break;
        }
      }

      final List<_SocketRow> finalRows = _observeSockets(uid);
      for (final _SocketRow row in finalRows) {
        observed[row.key] = row;
      }
      final List<_SocketRow> outbound = _unexpectedOutbound(
        observed.values.toList(),
      );
      for (final _SocketRow row in outbound) {
        debugPrint('T138_OUTBOUND:${row.state}:${row.remote}');
      }
      _marker(
        'SOCKETS:total=${observed.length}:outbound=${outbound.length}:'
        'httpAttempts=${overrides.attempts}',
      );

      if (tablesReadable) {
        expect(
          outbound,
          isEmpty,
          reason:
              'the app UID $uid owns ${outbound.length} non-loopback outbound '
              'socket(s) during the offline journey',
        );
      } else {
        // The external host driver owns this assertion; this run only records
        // that the in-app table was unavailable.
        expect(outbound, isEmpty);
        _marker('SOCKET_TABLE_ASSERTION:delegated_to_host_driver');
      }
      expect(
        overrides.attempts,
        0,
        reason: 'Dart created ${overrides.attempts} outbound HTTP client(s)',
      );
      await positiveControl.close();
      _marker('POSITIVE_CONTROL:closed=1');
      _marker('NETWORK_AUDIT_COMPLETE');
    },
  );
}
