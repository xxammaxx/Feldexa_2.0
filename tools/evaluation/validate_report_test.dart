// T032 evidence report validator tests.
//
// This is a dependency-free host test harness, not a package:test suite:
//   dart tools/evaluation/validate_report_test.dart
//
// It proves the schema loads, the canonical report template validates, and
// each document-level rule fails closed: evidence-class separation, status
// vocabulary, class-specific environment blocks, performance conditions,
// privacy, artifact bytes/hashes, self-reference, naming, index rows, and
// schema rejection of unsupported keywords.
//
// Host-only tooling. No SIMULATED, EMULATOR, or DEVICE evidence is produced.

import 'dart:convert';
import 'dart:io';

import 'validate_report.dart';

int _checks = 0;
int _failures = 0;

void main() {
  final File schemaFile = File.fromUri(
    File.fromUri(Platform.script).parent.uri.resolve('report_schema.json'),
  );
  late final ReportSchema schema;
  try {
    schema = ReportSchema.load(schemaFile);
  } on SchemaException catch (error) {
    stderr.writeln('cannot load report schema: $error');
    exitCode = 1;
    return;
  }

  _group('schema', () {
    _check('loads the committed schema', () {
      _expect(schema.sectionOrder.length == 11, 'expected 11 sections');
      _expect(schema.classEnvironment.length == 4, 'expected 4 classes');
    });
    _check('rejects invalid JSON', () {
      final File file = _temporaryFile('bad-json.json', '{');
      _expectThrows<SchemaException>(() => ReportSchema.load(file));
    });
    _check('rejects an unsupported JSON Schema keyword', () {
      final Map<String, Object?> document =
          jsonDecode(schemaFile.readAsStringSync()) as Map<String, Object?>;
      final Map<String, Object?> defs =
          document[r'$defs']! as Map<String, Object?>;
      final Map<String, Object?> title = defs['title']! as Map<String, Object?>;
      title['minProperties'] = 1;
      final File file = _temporaryFile(
        'unsupported-keyword.json',
        jsonEncode(document),
      );
      _expectThrows<SchemaException>(() => ReportSchema.load(file));
    });
    _check('rejects a missing schema file', () {
      _expectThrows<SchemaException>(
        () => ReportSchema.load(File('.dart_tool/does-not-exist.json')),
      );
    });
    _check('validates the known SHA-256 vector', () {
      _expect(
        sha256Hex(utf8.encode('abc')) ==
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        'SHA-256 test vector mismatch',
      );
      _expect(
        sha256Hex(<int>[]) ==
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'empty SHA-256 test vector mismatch',
      );
    });
  });

  _group('valid reports', () {
    _check('accepts a canonical NONE host report', () {
      final _Fixture fixture = _fixture('valid-none', schema);
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('accepts a canonical SIMULATED report', () {
      final _Fixture fixture = _fixture(
        'valid-simulated',
        schema,
        className: 'SIMULATED',
        slug: 'simulated-smoke',
        environment:
            'SIMULATED: browser Chromium 156; viewport 1280 x 720, DPR 1; '
            'Web build build/web SHA-256 ${_hash('web')}; '
            'simulated adapters web.sim.v1; fixtures sf-001; network offline.',
        buildIdentity: 'Web build build/web SHA-256 ${_hash('web')}',
        input: 'fixtures sf-001 SHA-256 ${_hash('fixture')}',
        checkCommand: 'flutter test --platform chrome',
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('accepts a canonical EMULATOR report', () {
      final _Fixture fixture = _fixture(
        'valid-emulator',
        schema,
        className: 'EMULATOR',
        slug: 'emulator-smoke',
        environment:
            'EMULATOR: Pixel 7 API 35, exclusive allocation env-a; '
            'system image google_apis; RAM 2048 MB; APK app-debug.apk '
            'SHA-256 ${_hash('apk')}; build mode debug; network offline.',
        buildIdentity: 'APK app-debug.apk SHA-256 ${_hash('apk')}',
        checkCommand: 'adb shell getprop',
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('accepts a DEVICE report with a complete T141 equivalent', () {
      final _Fixture fixture = _fixture(
        'valid-device',
        schema,
        className: 'DEVICE',
        slug: 'device-smoke',
        environment:
            'DEVICE: T141-approved equivalent; build fingerprint vendor/a54; '
            'APK app-release.apk SHA-256 ${_hash('apk')}; release; network '
            'offline.',
        buildIdentity: 'APK app-release.apk SHA-256 ${_hash('apk')}',
        checkCommand: 'adb shell getprop',
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('accepts a blank independent-review row', () {
      final _Fixture fixture = _fixture('blank-review', schema);
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
  });

  _group('class separation', () {
    _check('rejects a title/metadata class mismatch', () {
      final _Fixture fixture = _fixture(
        'class-mismatch',
        schema,
        className: 'SIMULATED',
        metadataClass: 'EMULATOR',
        slug: 'simulated-mismatch',
        environment:
            'SIMULATED: browser Chromium; viewport 1280 x 720; Web build '
            'SHA-256 ${_hash('web')}; simulated adapters web.sim.v1; fixtures '
            'sf-001; network offline.',
        checkCommand: 'flutter test --platform chrome',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'class.mismatch',
      );
    });
    _check('rejects a browser command in a NONE report', () {
      final _Fixture fixture = _fixture(
        'none-browser',
        schema,
        checkCommand: 'flutter test --platform chrome',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'class.runtime',
      );
    });
    _check('rejects an Android command in a SIMULATED report', () {
      final _Fixture fixture = _fixture(
        'simulated-android',
        schema,
        className: 'SIMULATED',
        slug: 'simulated-android',
        environment:
            'SIMULATED: browser Chromium; viewport 1280 x 720; Web build '
            'SHA-256 ${_hash('web')}; simulated adapters web.sim.v1; fixtures '
            'sf-001; network offline.',
        checkCommand: 'adb shell getprop',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'class.runtime',
      );
    });
    _check('rejects a SIMULATED report without its environment block', () {
      final _Fixture fixture = _fixture(
        'simulated-no-env',
        schema,
        className: 'SIMULATED',
        slug: 'simulated-no-env',
        environment: 'SIMULATED runtime.',
        checkCommand: 'flutter test --platform chrome',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'class.environment',
      );
    });
  });

  _group('structure and status', () {
    _check('rejects a missing required metadata field', () {
      final _Fixture fixture = _fixture(
        'missing-input',
        schema,
        omitInput: true,
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'parse.metadata.missing',
      );
    });
    _check('rejects an unknown metadata label', () {
      final _Fixture fixture = _fixture('metadata-unknown', schema);
      fixture.write(
        fixture.reportRelativePath,
        fixture.reportText.replaceFirst(
          '| Input |',
          '| Reviewer note | not in the template |\n| Input |',
        ),
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'parse.metadata.unknown',
      );
    });
    _check('accepts a legitimate metadata label with whitespace', () {
      final _Fixture fixture = _fixture('metadata-whitespace', schema);
      fixture.write(
        fixture.reportRelativePath,
        fixture.reportText.replaceFirst('| Input |', '|  Input  |'),
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('metadata diagnostics do not echo an untrusted label', () {
      final _Fixture fixture = _fixture('metadata-diagnostic-key', schema);
      fixture.write(
        fixture.reportRelativePath,
        fixture.reportText.replaceFirst(
          '| Input |',
          '| secret-label-abc | one |\n'
              '| secret-label-abc | two |\n'
              '| Input |',
        ),
      );
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expectInvalid(result, 'parse.metadata');
      _expect(
        !result.errors.any(
          (ValidationIssue issue) =>
              issue.toString().contains('secret-label-abc'),
        ),
        'metadata diagnostic echoed the untrusted label',
      );
    });
    _check('rejects a missing required section', () {
      final _Fixture fixture = _fixture('missing-performance', schema);
      fixture.write(
        fixture.reportRelativePath,
        fixture.reportText.replaceFirst(
          RegExp(r'## 6\. Performance[\s\S]*?## 7\.'),
          '## 7.',
        ),
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'parse.sections.missing',
      );
    });
    _check('rejects a compound PASS result', () {
      final _Fixture fixture = _fixture(
        'compound-pass',
        schema,
        result: '`PASS` with exceptions',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'parse.metadata',
      );
    });
    _check('rejects PASS with a failing check', () {
      final _Fixture fixture = _fixture(
        'pass-with-fail',
        schema,
        result: 'PASS',
        checkOutcome: 'FAIL',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'status.consistency',
      );
    });
    _check('rejects FAIL without a failing check', () {
      final _Fixture fixture = _fixture(
        'fail-without-fail',
        schema,
        result: 'FAIL',
        checkOutcome: 'PASS',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'status.consistency',
      );
    });
    _check('rejects a placeholder command', () {
      final _Fixture fixture = _fixture(
        'placeholder-command',
        schema,
        checkCommand: '<command>',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'parse.checks',
      );
    });
    _check('rejects a non-blank independent-review row', () {
      final _Fixture fixture = _fixture(
        'filled-review',
        schema,
        reviewRow: '| Reviewer | 2026-11-13 | PASS | looks good |',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'review.self',
      );
    });
  });

  _group('date and time', () {
    _check('rejects an impossible calendar date', () {
      final _Fixture fixture = _fixture(
        'invalid-date',
        schema,
        date: '2026-02-30',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'date.invalid',
      );
    });
    _check('rejects an impossible clock time', () {
      final _Fixture fixture = _fixture(
        'invalid-time',
        schema,
        timestampTime: '24:00',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'timestamp.invalid',
      );
    });
    _check('accepts a leap-day date', () {
      final _Fixture fixture = _fixture('leap-day', schema, date: '2024-02-29');
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
  });

  _group('performance', () {
    _check('rejects a timing claim without conditions', () {
      final _Fixture fixture = _fixture(
        'performance-no-conditions',
        schema,
        performance: 'The run took 900 ms.',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'performance.conditions',
      );
    });
    _check('rejects a three-second claim without the named device', () {
      final _Fixture fixture = _fixture(
        'performance-sc004',
        schema,
        performance:
            'Median 3 s on a Pixel 7, release build, corpus-1.0.0, '
            'one warm-up.',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'performance.sc004',
      );
    });
    _check('accepts a conditioned three-second claim', () {
      final _Fixture fixture = _fixture(
        'performance-sc004-ok',
        schema,
        className: 'EMULATOR',
        slug: 'emulator-performance',
        environment:
            'EMULATOR: Pixel 7 API 35, exclusive allocation env-b; '
            'system image google_apis; RAM 2048 MB; APK app-debug.apk '
            'SHA-256 ${_hash('apk')}; build mode release; network offline.',
        checkCommand: 'adb shell getprop',
        performance:
            'Samsung Galaxy A54 5G, release build, corpus-1.0.0, median '
            '3 s after one warm-up.',
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('rejects every schema SC-004 trigger without the named device', () {
      for (final String trigger in schema.performance.sc004Triggers) {
        final String slug = trigger.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
        final _Fixture fixture = _fixture(
          'sc004-trigger-$slug',
          schema,
          performance:
              '$trigger median on a Pixel 7, release build, corpus-1.0.0, '
              'one warm-up.',
        );
        _expectInvalid(
          validateReport(
            report: fixture.report,
            schema: schema,
            root: fixture.root,
            verifyGit: false,
          ),
          'performance.sc004',
        );
      }
    });
    _check('rejects a mixed no-claim and timing statement', () {
      final _Fixture fixture = _fixture(
        'performance-mixed-claim',
        schema,
        performance:
            'No performance claim. Median 3 s on a Pixel 7, release build, '
            'corpus-1.0.0, one warm-up.',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'performance.contradiction',
      );
    });
    _check('rejects a runtime performance claim in a NONE report', () {
      final _Fixture fixture = _fixture(
        'performance-none',
        schema,
        performance:
            'Median 12 ms on the host, release build, corpus fixtures, '
            'three runs.',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'performance.class',
      );
    });
  });

  _group('privacy and self-reference', () {
    _check('rejects an absolute host path without echoing it', () {
      final _Fixture fixture = _fixture(
        'privacy-path',
        schema,
        limitations: 'See /home/example/private/notes.txt for details.',
      );
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expectInvalid(result, 'privacy.content');
      _expect(
        !result.errors.any(
          (ValidationIssue issue) =>
              issue.toString().contains('example/private'),
        ),
        'privacy finding echoed the forbidden path',
      );
    });
    _check('rejects a raw terminal identifier without echoing it', () {
      final _Fixture fixture = _fixture(
        'privacy-id',
        schema,
        limitations: 'Captured under term_deadbeef1234 for this run.',
      );
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expectInvalid(result, 'privacy.content');
      _expect(
        !result.errors.any(
          (ValidationIssue issue) =>
              issue.toString().contains('term_deadbeef1234'),
        ),
        'privacy finding echoed the raw terminal identifier',
      );
    });
    _check('rejects a system path such as /etc without echoing it', () {
      final _Fixture fixture = _fixture(
        'privacy-etc',
        schema,
        limitations: 'See /etc/passwd for details.',
      );
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expectInvalid(result, 'privacy.content');
      _expect(
        !result.errors.any(
          (ValidationIssue issue) => issue.toString().contains('/etc/passwd'),
        ),
        'privacy finding echoed the forbidden system path',
      );
    });
    _check('rejects all Windows absolute path forms', () {
      final List<String> paths = <String>[
        r'D:\SDK\private\workspace',
        'D:/SDK/private',
        r'\\server\share\private',
        r'\\?\C:\SDK\private',
        'file:///D:/SDK/private',
        'file://server/share/private',
      ];
      for (int index = 0; index < paths.length; index++) {
        final _Fixture fixture = _fixture(
          'windows-path-$index',
          schema,
          limitations: 'Embedded at ${paths[index]} for review.',
        );
        final ReportValidation result = validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        );
        _expectInvalid(result, 'privacy.content');
        _expect(
          !result.errors.any(
            (ValidationIssue issue) => issue.toString().contains(paths[index]),
          ),
          'privacy diagnostic echoed the Windows path',
        );
      }
    });
    _check('rejects scheme-relative URLs and forward UNC as ambiguous', () {
      final List<String> paths = <String>[
        '//server/share/private',
        '//cdn.example.com/path',
      ];
      for (int index = 0; index < paths.length; index++) {
        final _Fixture fixture = _fixture(
          'scheme-relative-$index',
          schema,
          limitations: 'Embedded at ${paths[index]} for review.',
        );
        final ReportValidation result = validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        );
        _expectInvalid(result, 'privacy.content');
        _expect(
          !result.errors.any(
            (ValidationIssue issue) => issue.toString().contains(paths[index]),
          ),
          'privacy diagnostic echoed the scheme-relative path',
        );
      }
    });
    _check('rejects extended and device namespace absolute paths', () {
      final List<String> paths = <String>[
        r'\\?\UNC\server\share\private',
        r'\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1',
        r'\\?\Volume{1234}\private',
        r'\\?\PIPE\private',
        r'\\.\PhysicalDrive0',
        r'\??\C:\SDK\private',
        '//?/UNC/server/share/private',
      ];
      for (int index = 0; index < paths.length; index++) {
        final _Fixture fixture = _fixture(
          'namespace-path-$index',
          schema,
          limitations: 'Embedded at ${paths[index]} for review.',
        );
        final ReportValidation result = validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        );
        _expectInvalid(result, 'privacy.content');
        _expect(
          !result.errors.any(
            (ValidationIssue issue) => issue.toString().contains(paths[index]),
          ),
          'privacy diagnostic echoed the namespace path',
        );
      }
    });
    _check('rejects rooted NT and Windows backslash paths', () {
      final List<String> paths = <String>[
        r'\Device\HarddiskVolume1\Users\private',
        r'\REGISTRY\MACHINE\SOFTWARE\private',
        r'\GLOBALROOT\Device\HarddiskVolume1\Users',
        r'\DosDevices\C:\SDK\private',
        r'\??\C:\SDK\private',
      ];
      for (int index = 0; index < paths.length; index++) {
        final _Fixture fixture = _fixture(
          'rooted-path-$index',
          schema,
          limitations: 'Embedded at ${paths[index]} for review.',
        );
        final ReportValidation result = validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        );
        _expectInvalid(result, 'privacy.content');
        _expect(
          !result.errors.any(
            (ValidationIssue issue) => issue.toString().contains(paths[index]),
          ),
          'privacy diagnostic echoed the rooted path',
        );
      }
    });
    _check('accepts URL and relative-path lookalikes', () {
      final List<String> values = <String>[
        'https://example.com/path',
        'https://example.com/C:/path',
        'http://cdn.example.com/path',
        'https://cdn.example.com/path',
        r'SDK\private',
        r'Use \n for a newline.',
        r'Use \alpha as a symbol.',
        r'folder\subfolder',
      ];
      for (int index = 0; index < values.length; index++) {
        final _Fixture fixture = _fixture(
          'windows-false-positive-$index',
          schema,
          limitations: 'Context: ${values[index]}',
        );
        _expectValid(
          validateReport(
            report: fixture.report,
            schema: schema,
            root: fixture.root,
            verifyGit: false,
          ),
        );
      }
    });
    _check('rejects the report listing itself as an artifact', () {
      final _Fixture fixture = _fixture('self-artifact', schema);
      fixture.write(
        fixture.reportRelativePath,
        fixture.reportText.replaceFirst(
          RegExp(r'\| artifact \| `artifact\.bin` \|[^\n]*'),
          '| self | `${fixture.reportRelativePath}` | 1 | `${_hash('self')}` |',
        ),
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'self.reference',
      );
    });
  });

  _group('artifacts', () {
    _check('rejects a mismatched artifact hash', () {
      final _Fixture fixture = _fixture(
        'artifact-hash',
        schema,
        artifactHash: _hash('wrong'),
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'artifact.hash',
      );
    });
    _check('rejects a missing artifact by default', () {
      final _Fixture fixture = _fixture(
        'artifact-missing',
        schema,
        writeArtifact: false,
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'artifact.missing',
      );
    });
    _check('allows a missing artifact only with the explicit option', () {
      final _Fixture fixture = _fixture(
        'artifact-missing-allowed',
        schema,
        writeArtifact: false,
      );
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
        allowMissingArtifacts: true,
      );
      _expectValid(result);
      _expect(
        result.warnings.isNotEmpty,
        'expected a missing-artifact warning',
      );
    });
    _check('artifact diagnostics do not echo an untrusted path', () {
      final _Fixture fixture = _fixture(
        'artifact-diagnostic-path',
        schema,
        artifactPath: 'sensitive/private-note.txt',
        writeArtifact: false,
      );
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expectInvalid(result, 'artifact.missing');
      _expect(
        !result.errors.any(
          (ValidationIssue issue) =>
              issue.toString().contains('sensitive/private-note.txt'),
        ),
        'artifact diagnostic echoed the untrusted path',
      );
    });
    _check('artifact duplicate-path diagnostics do not echo the path', () {
      final _Fixture fixture = _fixture(
        'artifact-diagnostic-duplicate',
        schema,
      );
      fixture.write(
        fixture.reportRelativePath,
        fixture.reportText.replaceFirst(
          RegExp(r'\| artifact \| `artifact\.bin` \|[^\n]*'),
          '| a | `sensitive/private-note.txt` | 9 | `${_hash('artifact')}` |\n'
          '| b | `sensitive/private-note.txt` | 9 | `${_hash('artifact')}` |',
        ),
      );
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expectInvalid(result, 'parse.artifacts');
      _expect(
        !result.errors.any(
          (ValidationIssue issue) =>
              issue.toString().contains('sensitive/private-note.txt'),
        ),
        'duplicate-artifact diagnostic echoed the untrusted path',
      );
    });
    _check('rejects an absolute artifact path', () {
      final _Fixture fixture = _fixture(
        'artifact-absolute',
        schema,
        artifactPath: '/home/example/artifact.bin',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'artifact.path',
      );
    });
  });

  _group('check logs and class blocks', () {
    _check('accepts a retained check log with an artifact row', () {
      final _Fixture fixture = _fixture(
        'retained-log',
        schema,
        checkLog: 'logs/check.log',
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('rejects a retained check log missing from the artifacts table', () {
      final _Fixture fixture = _fixture(
        'retained-log-missing',
        schema,
        checkLog: 'logs/check.log',
        writeLogArtifact: false,
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'checks.log',
      );
    });
    _check('rejects an UNAVAILABLE check that names a retained log', () {
      final _Fixture fixture = _fixture(
        'unavailable-log',
        schema,
        result: 'PARTIAL',
        checkOutcome: 'UNAVAILABLE',
        checkExit: '-',
        checkLog: 'logs/check.log',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'checks.log',
      );
    });
    _check('rejects a runtime class block in a NONE environment', () {
      final _Fixture fixture = _fixture(
        'none-runtime-block',
        schema,
        environment: 'Host VM; SIMULATED: browser Chromium.',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'class.environment',
      );
    });
    _check('rejects multiple class blocks in one environment', () {
      final _Fixture fixture = _fixture(
        'simulated-multi-block',
        schema,
        className: 'SIMULATED',
        slug: 'simulated-multi',
        environment:
            'SIMULATED: browser Chromium; viewport 1280 x 720; Web build '
            'SHA-256 ${_hash('web')}; simulated adapters web.sim.v1; fixtures '
            'sf-001; network offline. DEVICE: Samsung Galaxy A54 5G.',
        checkCommand: 'flutter test --platform chrome',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'class.environment',
      );
    });
  });

  _group('exit codes and symlink containment', () {
    _check('rejects PASS with a non-zero exit code', () {
      final _Fixture fixture = _fixture(
        'pass-exit-one',
        schema,
        checkExit: '1',
        checkOutcome: 'PASS',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'status.exitcode',
      );
    });
    _check('rejects FAIL with a zero exit code', () {
      final _Fixture fixture = _fixture(
        'fail-exit-zero',
        schema,
        result: 'FAIL',
        checkExit: '0',
        checkOutcome: 'FAIL',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'status.exitcode',
      );
    });
    _check('accepts FAIL with a non-zero exit code', () {
      final _Fixture fixture = _fixture(
        'fail-exit-one',
        schema,
        result: 'FAIL',
        checkExit: '1',
        checkOutcome: 'FAIL',
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('accepts a not-run check with the "-" exit sentinel', () {
      final _Fixture fixture = _fixture(
        'unavailable-dash',
        schema,
        result: 'PARTIAL',
        checkExit: '-',
        checkOutcome: 'UNAVAILABLE',
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('rejects a not-run check with a shell exit code', () {
      final _Fixture fixture = _fixture(
        'unavailable-zero',
        schema,
        result: 'PARTIAL',
        checkExit: '0',
        checkOutcome: 'UNAVAILABLE',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'status.exitcode',
      );
    });
    _check('rejects an artifact symlink escaping the repository', () {
      final String outside = _outsideFile('artifact-escape.bin', 'outside\n');
      final _Fixture fixture = _fixture(
        'artifact-symlink-escape',
        schema,
        artifactPath: 'escape.bin',
        artifactSymlinkTarget: outside,
        artifactContent: 'outside\n',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'artifact.symlink',
      );
    });
    _check('accepts an artifact symlink that stays inside the repository', () {
      final _Fixture fixture = _fixture(
        'artifact-symlink-inside',
        schema,
        artifactPath: 'link.bin',
        artifactSymlinkTarget: 'artifact.bin',
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('rejects a dirty-file symlink escaping the repository', () {
      final String outside = _outsideFile('dirty-escape.bin', 'outside\n');
      final _Fixture fixture = _fixture(
        'dirty-symlink-escape',
        schema,
        treeState: 'dirty',
        dirtyFile: 'escape.bin',
        dirtyHash: _hash('outside\n'),
        dirtySymlinkTarget: outside,
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'metadata.tree',
      );
    });
    _check('accepts a dirty-file symlink that stays inside the repository', () {
      final _Fixture fixture = _fixture(
        'dirty-symlink-inside',
        schema,
        treeState: 'dirty',
        dirtyFile: 'link.bin',
        dirtyHash: sha256Hex(utf8.encode('artifact\n')),
        dirtySymlinkTarget: 'artifact.bin',
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
    _check('dirty diagnostics do not echo an untrusted path', () {
      final _Fixture fixture = _fixture(
        'dirty-diagnostic-path',
        schema,
        treeState: 'dirty',
        dirtyFile: 'sensitive/private-note.txt',
        dirtyHash: _hash('artifact\n'),
      );
      File('${fixture.root.path}/sensitive/private-note.txt').deleteSync();
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expectInvalid(result, 'metadata.tree');
      _expect(
        !result.errors.any(
          (ValidationIssue issue) =>
              issue.toString().contains('sensitive/private-note.txt'),
        ),
        'dirty diagnostic echoed the untrusted path',
      );
    });
    _check('rejects an unreadable dirty file without throwing', () {
      final String uid = Process.runSync('id', <String>[
        '-u',
      ]).stdout.toString().trim();
      if (uid == '0') {
        return;
      }
      final _Fixture fixture = _fixture(
        'dirty-unreadable',
        schema,
        treeState: 'dirty',
        dirtyFile: 'unreadable.bin',
        dirtyHash: _hash('unreadable\n'),
        artifactContent: 'unreadable\n',
      );
      final File file = File('${fixture.root.path}/unreadable.bin');
      Process.runSync('chmod', <String>['000', file.path]);
      try {
        _expectInvalid(
          validateReport(
            report: fixture.report,
            schema: schema,
            root: fixture.root,
            verifyGit: false,
          ),
          'metadata.tree',
        );
      } finally {
        Process.runSync('chmod', <String>['644', file.path]);
      }
    });
    _check('rejects an artifact path whose parent is a symlink escape', () {
      final Directory outside = Directory(
        '.dart_tool/validate_report_test/outside-artifact-parent',
      )..createSync(recursive: true);
      File('${outside.path}/artifact.bin').writeAsStringSync('outside-dir\n');
      final _Fixture fixture = _fixture(
        'artifact-parent-symlink',
        schema,
        artifactPath: 'linkdir/artifact.bin',
        artifactContent: 'outside-dir\n',
      );
      final Directory linkdir = Directory('${fixture.root.path}/linkdir');
      if (linkdir.existsSync()) {
        linkdir.deleteSync(recursive: true);
      }
      Link(linkdir.path).createSync(outside.absolute.path);
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'artifact.symlink',
      );
    });
    _check('rejects a dirty-file path whose parent is a symlink escape', () {
      final Directory outside = Directory(
        '.dart_tool/validate_report_test/outside-dirty-parent',
      )..createSync(recursive: true);
      File('${outside.path}/artifact.bin').writeAsStringSync('artifact\n');
      final _Fixture fixture = _fixture(
        'dirty-parent-symlink',
        schema,
        treeState: 'dirty',
        dirtyFile: 'linkdir/artifact.bin',
        dirtyHash: sha256Hex(utf8.encode('artifact\n')),
      );
      final Directory linkdir = Directory('${fixture.root.path}/linkdir');
      if (linkdir.existsSync()) {
        linkdir.deleteSync(recursive: true);
      }
      Link(linkdir.path).createSync(outside.absolute.path);
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'metadata.tree',
      );
    });
    _check('rejects a dirty path that is a directory', () {
      final _Fixture fixture = _fixture(
        'dirty-directory',
        schema,
        treeState: 'dirty',
        dirtyFile: 'dirty-dir',
        dirtyHash: _hash('artifact\n'),
        dirtyIsDirectory: true,
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'metadata.tree',
      );
    });
  });

  _group('naming, index, and tree state', () {
    _check('rejects a file-name date mismatch', () {
      final _Fixture fixture = _fixture(
        'date-mismatch',
        schema,
        fileName: '2026-11-14-t032-evidence.md',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'naming.date',
      );
    });
    _check('rejects a missing index row', () {
      final _Fixture fixture = _fixture(
        'missing-index',
        schema,
        writeIndexRow: false,
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'index.missing',
      );
    });
    _check('rejects an index class mismatch', () {
      final _Fixture fixture = _fixture(
        'index-class',
        schema,
        indexClass: 'DEVICE',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'index.class',
      );
    });
    _check('index missing-row diagnostics do not echo the report name', () {
      final _Fixture fixture = _fixture(
        'index-diagnostic-name',
        schema,
        fileName: '2026-11-13-t032-sensitive-name.md',
        writeIndexRow: false,
      );
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expectInvalid(result, 'index.missing');
      _expect(
        !result.errors.any(
          (ValidationIssue issue) =>
              issue.toString().contains('sensitive-name'),
        ),
        'index diagnostic echoed the untrusted report name',
      );
    });
    _check('index class diagnostics do not echo the index value', () {
      final _Fixture fixture = _fixture(
        'index-diagnostic-class',
        schema,
        indexClass: 'SENSITIVE-CLASS-TOKEN',
      );
      final ReportValidation result = validateReport(
        report: fixture.report,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expectInvalid(result, 'index.class');
      _expect(
        !result.errors.any(
          (ValidationIssue issue) =>
              issue.toString().contains('SENSITIVE-CLASS-TOKEN'),
        ),
        'index diagnostic echoed the untrusted class value',
      );
    });
    _check('rejects an unreadable index without throwing', () {
      final String uid = Process.runSync('id', <String>[
        '-u',
      ]).stdout.toString().trim();
      if (uid == '0') {
        return;
      }
      final _Fixture fixture = _fixture('index-unreadable', schema);
      final File index = File(
        '${fixture.root.path}/${schema.evidenceRoot}/${schema.indexFile}',
      );
      Process.runSync('chmod', <String>['000', index.path]);
      try {
        _expectInvalid(
          validateReport(
            report: fixture.report,
            schema: schema,
            root: fixture.root,
            verifyGit: false,
          ),
          'index.unreadable',
        );
      } finally {
        Process.runSync('chmod', <String>['644', index.path]);
      }
    });
    _check('rejects an index symlink escaping the repository', () {
      final _Fixture fixture = _fixture('index-symlink-escape', schema);
      final Directory outside = Directory(
        '.dart_tool/validate_report_test/outside-index',
      )..createSync(recursive: true);
      final File outsideIndex = File('${outside.path}/README.md')
        ..writeAsStringSync('# Outside\n');
      final File index = File(
        '${fixture.root.path}/${schema.evidenceRoot}/${schema.indexFile}',
      );
      index.deleteSync();
      Link(index.path).createSync(outsideIndex.absolute.path);
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'index.unreadable',
      );
    });
    _check('rejects a dirty tree without per-file hashes', () {
      final _Fixture fixture = _fixture(
        'dirty-no-files',
        schema,
        treeState: 'dirty',
      );
      _expectInvalid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
        'metadata.tree',
      );
    });
    _check('accepts a dirty tree with per-file hashes', () {
      final _Fixture fixture = _fixture(
        'dirty-with-files',
        schema,
        treeState: 'dirty',
        dirtyFile: 'artifact.bin',
        dirtyHash: sha256Hex(utf8.encode('artifact\n')),
      );
      _expectValid(
        validateReport(
          report: fixture.report,
          schema: schema,
          root: fixture.root,
          verifyGit: false,
        ),
      );
    });
  });

  _group('output paths', () {
    _check('sanitizes an outside-root failed-read path', () {
      final _Fixture fixture = _fixture('failed-read-outside', schema);
      final File missing = File(
        '${fixture.root.parent.absolute.path}/private/nope.md',
      );
      final ReportValidation result = validateReport(
        report: missing,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expect(!result.valid, 'expected an invalid result');
      _expect(
        result.errors.any((ValidationIssue issue) => issue.code == 'io.report'),
        'expected io.report',
      );
      _expect(
        result.path == 'nope.md',
        'expected basename path, got ${result.path}',
      );
      _expect(
        !result.path.contains(fixture.root.parent.absolute.path),
        'failed-read path leaked the private parent path',
      );
    });
    _check('sanitizes an inside-root failed-read path', () {
      final _Fixture fixture = _fixture('failed-read-inside', schema);
      final File missing = File(
        '${fixture.root.absolute.path}/${schema.evidenceRoot}/'
        '2026-11-13-t032-missing.md',
      );
      final ReportValidation result = validateReport(
        report: missing,
        schema: schema,
        root: fixture.root,
        verifyGit: false,
      );
      _expect(!result.valid, 'expected an invalid result');
      _expect(
        result.path == '2026-11-13-t032-missing.md',
        'expected basename path, got ${result.path}',
      );
      _expect(
        !result.path.contains(fixture.root.absolute.path),
        'failed-read path leaked the absolute root',
      );
    });
    _check('sanitizes an outside-root valid report path in JSON', () {
      final _Fixture fixture = _fixture('outside-path', schema);
      final File outside = File(
        '.dart_tool/validate_report_test/outside-path/'
        '2026-11-13-t032-outside.md',
      );
      outside.parent.createSync(recursive: true);
      outside.writeAsStringSync(fixture.reportText);
      final ReportValidation result = validateReport(
        report: outside.absolute,
        schema: schema,
        root: fixture.root,
        checkIndex: false,
        checkLayout: false,
        verifyGit: false,
      );
      _expect(
        result.valid,
        'expected a valid outside-root report, got ${result.errors}',
      );
      _expect(
        result.path == '2026-11-13-t032-outside.md',
        'expected basename path, got ${result.path}',
      );
      _expect(
        !result.path.contains(Directory.current.absolute.path),
        'JSON path leaked the absolute working directory',
      );
      _expect(
        result.toJson()['path'] == '2026-11-13-t032-outside.md',
        'JSON serialization used an unsanitized path',
      );
    });
  });

  _group('command line', () {
    _check('schema-check succeeds', () {
      _expect(
        runValidatorCli(<String>[
              '--schema-check',
              '--schema',
              schemaFile.path,
            ], quiet: true) ==
            0,
        'schema-check should return 0',
      );
    });
    _check('usage errors return 2', () {
      _expect(
        runValidatorCli(<String>[], quiet: true) == 2,
        'empty invocation should return 2',
      );
      _expect(
        runValidatorCli(<String>[
              '--schema-check',
              '--schema',
              'missing.json',
            ], quiet: true) ==
            2,
        'missing schema should return 2',
      );
    });
  });

  stdout.writeln('');
  stdout.writeln('$_checks checks, $_failures failure(s)');
  if (_failures > 0) {
    exitCode = 1;
  }
}

void _group(String name, void Function() body) {
  stdout.writeln('== $name ==');
  body();
}

void _check(String name, void Function() body) {
  _checks++;
  try {
    body();
    stdout.writeln('PASS $name');
  } catch (error) {
    _failures++;
    stdout.writeln('FAIL $name: $error');
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void _expectValid(ReportValidation result) {
  _expect(
    result.valid,
    'expected valid report, got: ${result.errors.join('; ')}',
  );
}

void _expectInvalid(ReportValidation result, String code) {
  _expect(!result.valid, 'expected an invalid report');
  _expect(
    result.errors.any((ValidationIssue issue) => issue.code == code),
    'expected error $code, got: ${result.errors.join('; ')}',
  );
}

void _expectThrows<T extends Object>(void Function() body) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T');
}

String _hash(String value) => sha256Hex(utf8.encode(value));

File _temporaryFile(String name, String content) {
  final Directory directory = Directory('.dart_tool/validate_report_test');
  directory.createSync(recursive: true);
  final File file = File('${directory.path}/$name');
  file.writeAsStringSync(content);
  return file;
}

String _outsideFile(String name, String content) {
  final Directory directory = Directory(
    '.dart_tool/validate_report_test/outside',
  );
  directory.createSync(recursive: true);
  final File file = File('${directory.path}/$name');
  file.writeAsStringSync(content);
  return file.absolute.path;
}

class _Fixture {
  _Fixture({
    required this.root,
    required this.report,
    required this.reportRelativePath,
    required this.reportName,
    required this.reportText,
  });

  final Directory root;
  final File report;
  final String reportRelativePath;
  final String reportName;
  final String reportText;

  void write(String path, String content) {
    File('${root.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }
}

_Fixture _fixture(
  String name,
  ReportSchema schema, {
  String className = 'NONE',
  String metadataClass = '',
  String result = 'PASS',
  String date = '2026-11-13',
  String timestampTime = '11:30',
  String task = 'T032',
  int issue = 32,
  String slug = '',
  String? fileName,
  String baseCommit = '4932af4b53cc5932fa583650214c9cebb8f901c2',
  String treeState = 'clean',
  String? dirtyFile,
  String? dirtyHash,
  String? environment,
  String? buildIdentity,
  String? input,
  String checkCommand = 'dart tools/evaluation/validate_report.dart',
  String checkExit = '0',
  String checkLog = 'console only (not retained)',
  String checkOutcome = 'PASS',
  bool writeLogArtifact = true,
  String? artifactSymlinkTarget,
  String? dirtySymlinkTarget,
  bool dirtyIsDirectory = false,
  String artifactContent = 'artifact\n',
  String limitations = 'Host-only tooling; no runtime evidence.',
  String performance = 'No performance claim.',
  String? artifactPath,
  String? artifactHash,
  bool writeArtifact = true,
  bool omitInput = false,
  bool writeIndexRow = true,
  String indexClass = '',
  String reviewRow = '|  |  |  |  |',
}) {
  final String defaultSlug = className == 'NONE'
      ? 't032-evidence'
      : '${className.toLowerCase()}-evidence';
  final String effectiveSlug = slug.isEmpty ? defaultSlug : slug;
  final String effectiveName = fileName ?? '$date-$effectiveSlug.md';
  final Directory root = Directory('.dart_tool/validate_report_test/$name');
  if (root.existsSync()) {
    root.deleteSync(recursive: true);
  }
  final Directory evidenceRoot = Directory(
    '${root.path}/${schema.evidenceRoot}',
  )..createSync(recursive: true);
  final String relative = '${schema.evidenceRoot}/$effectiveName';
  final File report = File('${root.path}/$relative');
  report.parent.createSync(recursive: true);

  const Set<String> noLogLabels = <String>{
    'console only (not retained)',
    'none',
    'n/a',
    'not run',
    'no log',
  };
  final bool retainedLog = !noLogLabels.contains(checkLog.toLowerCase());
  final String logContent = 'check log\n';
  final int logBytes = utf8.encode(logContent).length;
  final String logHash = sha256Hex(utf8.encode(logContent));
  if (retainedLog) {
    File('${root.path}/$checkLog')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(logContent);
  }
  final String logArtifactRow = retainedLog && writeLogArtifact
      ? '| check log | `$checkLog` | $logBytes | `$logHash` |\n'
      : '';

  final String effectiveArtifactPath = artifactPath ?? 'artifact.bin';
  final String effectiveArtifactHash =
      artifactHash ?? sha256Hex(utf8.encode(artifactContent));
  final int artifactBytes = utf8.encode(artifactContent).length;
  if (writeArtifact) {
    File('${root.path}/artifact.bin')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(artifactContent);
  }
  if (artifactSymlinkTarget != null) {
    Link('${root.path}/$effectiveArtifactPath')
      ..parent.createSync(recursive: true)
      ..createSync(artifactSymlinkTarget);
  } else if (writeArtifact && effectiveArtifactPath != 'artifact.bin') {
    File('${root.path}/$effectiveArtifactPath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(artifactContent);
  }
  if (dirtyFile != null) {
    final FileSystemEntity entity =
        FileSystemEntity.typeSync('${root.path}/$dirtyFile') ==
            FileSystemEntityType.notFound
        ? Link('${root.path}/$dirtyFile')
        : File('${root.path}/$dirtyFile');
    if (dirtySymlinkTarget != null) {
      entity.parent.createSync(recursive: true);
      Link('${root.path}/$dirtyFile').createSync(dirtySymlinkTarget);
    } else if (dirtyIsDirectory) {
      Directory('${root.path}/$dirtyFile').createSync(recursive: true);
    } else if (!entity.existsSync()) {
      File('${root.path}/$dirtyFile')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(artifactContent);
    }
  }

  if (writeIndexRow) {
    final String indexedClass = indexClass.isEmpty ? className : indexClass;
    File('${evidenceRoot.path}/${schema.indexFile}').writeAsStringSync('''
# Evidence Reports

| Report | Class | Kind | Notes |
| --- | --- | --- | --- |
| [$effectiveName](./$effectiveName) | `$indexedClass` | Test | Fixture |
''');
  } else {
    File('${evidenceRoot.path}/${schema.indexFile}')
        .writeAsStringSync('# Evidence Reports\n\nNo rows.\n');
  }

  final String effectiveMetadataClass = metadataClass.isEmpty
      ? className
      : metadataClass;
  final String effectiveEnvironment =
      environment ?? 'Host VM; no runtime class.';
  final String effectiveBuildIdentity =
      buildIdentity ?? 'host-only Dart validator; no app or Web build produced';
  final String effectiveInput = input ?? 'validator fixtures; no corpus input';
  final String revisionExtras = <String>[
    if (dirtyFile != null)
      'dirty files: `$dirtyFile` SHA-256 `${dirtyHash ?? sha256Hex(utf8.encode('artifact\n'))}`',
  ].join('; ');
  final String revision =
      'base commit `$baseCommit`; tree `$treeState`'
      '${revisionExtras.isEmpty ? '' : '; $revisionExtras'}; '
      'candidate SHA in external attestation';

  final String text =
      '''
# $date $className — T032 test report

| Field | Value |
| --- | --- |
| Evidence class | `$effectiveMetadataClass` |
| Result | `$result` |
| Task / issue | `$task` / #$issue |
| Date / timezone | `$date $timestampTime Europe/Berlin` |
| Revision | $revision |
| External attestation | worker_done transport attestation |
| Build identity | $effectiveBuildIdentity |
| Toolchain | Flutter `3.47.7`, Dart `3.13.5` |
${omitInput ? '' : '| Input | $effectiveInput |\n'}

## 1. Scope

Host-only T032 validator test fixture.

## 2. Revision and build

The recorded tree is $treeState.

## 3. Environment

$effectiveEnvironment

## 4. Checks

| # | Command (cwd) | Exit | Log | Outcome |
| ---: | --- | ---: | --- | --- |
| 1 | `$checkCommand` (`root`) | `$checkExit` | `$checkLog` | `$checkOutcome` |

## 5. Results

The checks and their outcomes are recorded above.

## 6. Performance

$performance

## 7. Limitations

$limitations

## 8. Artifacts

| Artifact | Path | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| artifact | `$effectiveArtifactPath` | $artifactBytes | `$effectiveArtifactHash` |
$logArtifactRow
## 9. Reproducibility

1. Run the validator on this fixture.

## 10. External attestation

Recorded in worker_done.

## 11. Independent review (author leaves blank)

| Reviewer | Date | Verdict | Notes |
| --- | --- | --- | --- |
$reviewRow
''';
  report.writeAsStringSync(text);
  return _Fixture(
    root: root,
    report: report,
    reportRelativePath: relative,
    reportName: effectiveName,
    reportText: text,
  );
}
