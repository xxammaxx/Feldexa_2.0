// T022 export artifact and state-machine tests.
//
// These are host-VM tests (`NONE` evidence). They pin `data-model.md` §3.15,
// `contracts/export-plan.md` §1/§4/§6, and FR-072: a failed or partial attempt
// never carries success metadata, and `succeeded` is reachable only after an
// all-passing verification. They cannot prove Android export behavior.
import 'dart:convert';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sha256 =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

String _uuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

DateTime _at([int minute = 0]) => DateTime.utc(2026, 11, 14, 12, minute);

ArtifactVerification _verification({
  bool pageCountMatches = true,
  bool mediaBoxesMatch = true,
  bool fontGlyphsPresent = true,
  bool noInteractiveFields = true,
  bool overlayBoundsWithinPage = true,
  DateTime? checkedAt,
  Map<String, Object?> unknownFields = const {},
}) {
  return ArtifactVerification(
    pageCountMatches: pageCountMatches,
    mediaBoxesMatch: mediaBoxesMatch,
    fontGlyphsPresent: fontGlyphsPresent,
    noInteractiveFields: noInteractiveFields,
    overlayBoundsWithinPage: overlayBoundsWithinPage,
    checkedAt: checkedAt ?? _at(1),
    unknownFields: unknownFields,
  );
}

ExportArtifact _start({Map<String, Object?> unknownFields = const {}}) {
  return ExportArtifact.start(
    id: _uuid(100),
    documentId: _uuid(101),
    revisionId: _uuid(102),
    pageCount: 2,
    createdAt: _at(),
    unknownFields: unknownFields,
  );
}

ExportArtifact _verifying() {
  return _start().startRendering().startVerification();
}

ExportArtifact _succeeded({ArtifactVerification? verification}) {
  return _verifying().succeed(
    byteSize: 4096,
    sha256: _sha256,
    verification: verification ?? _verification(),
  );
}

void main() {
  group('ArtifactVerification', () {
    test('requires five passing checks and UTC time', () {
      final ArtifactVerification verification = _verification();
      expect(verification.allChecksPassed, isTrue);
      expect(verification.checkedAt, _at(1));

      final ArtifactVerification restored = ArtifactVerification.fromJson(
        jsonDecode(jsonEncode(verification.toJson())) as Map<String, Object?>,
      );
      expect(restored, verification);

      expect(
        () => ArtifactVerification(
          pageCountMatches: true,
          mediaBoxesMatch: true,
          fontGlyphsPresent: true,
          noInteractiveFields: true,
          overlayBoundsWithinPage: true,
          checkedAt: DateTime(2026, 11, 14, 12),
        ),
        throwsArgumentError,
      );
    });

    test('allChecksPassed is false when any single check fails', () {
      expect(_verification(pageCountMatches: false).allChecksPassed, isFalse);
      expect(_verification(mediaBoxesMatch: false).allChecksPassed, isFalse);
      expect(_verification(fontGlyphsPresent: false).allChecksPassed, isFalse);
      expect(
        _verification(noInteractiveFields: false).allChecksPassed,
        isFalse,
      );
      expect(
        _verification(overlayBoundsWithinPage: false).allChecksPassed,
        isFalse,
      );
    });
  });

  group('ExportArtifact state machine', () {
    test('starts in validating and refuses every shortcut', () {
      final ExportArtifact artifact = _start();
      expect(artifact.state, ExportArtifactState.validating);
      expect(artifact.state.wireName, 'validating');
      expect(artifact.pageCount, 2);
      expect(artifact.byteSize, isNull);
      expect(artifact.sha256, isNull);
      expect(artifact.verification, isNull);
      expect(artifact.failureCode, isNull);
      expect(artifact.isPreviewAvailable, isFalse);
      expect(artifact.isTerminal, isFalse);
      expect(artifact.isBlocked, isFalse);

      expect(artifact.startVerification, throwsStateError);
      expect(
        () => artifact.succeed(
          byteSize: 1,
          sha256: _sha256,
          verification: _verification(),
        ),
        throwsStateError,
      );
      expect(artifact.markDeleted, throwsStateError);
    });

    test(
      'advances validating -> rendering -> verifying -> succeeded -> deleted',
      () {
        final ExportArtifact rendering = _start().startRendering();
        expect(rendering.state, ExportArtifactState.rendering);
        expect(rendering.isPreviewAvailable, isFalse);

        final ExportArtifact verifying = rendering.startVerification();
        expect(verifying.state, ExportArtifactState.verifying);
        expect(verifying.isPreviewAvailable, isFalse);

        final ArtifactVerification verification = _verification();
        final ExportArtifact succeeded = verifying.succeed(
          byteSize: 4096,
          sha256: _sha256,
          verification: verification,
        );
        expect(succeeded.state, ExportArtifactState.succeeded);
        expect(succeeded.state.wireName, 'succeeded');
        expect(succeeded.isPreviewAvailable, isTrue);
        expect(succeeded.isTerminal, isFalse);
        expect(succeeded.pageCount, 2);
        expect(succeeded.byteSize, 4096);
        expect(succeeded.sha256, _sha256);
        expect(succeeded.verification, verification);
        expect(succeeded.failureCode, isNull);
        expect(succeeded.isBlocked, isFalse);

        final ExportArtifact deleted = succeeded.markDeleted();
        expect(deleted.state, ExportArtifactState.deleted);
        expect(deleted.state.wireName, 'deleted');
        expect(deleted.isPreviewAvailable, isFalse);
        expect(deleted.isTerminal, isTrue);
        expect(deleted.byteSize, 4096);
        expect(deleted.sha256, _sha256);
        expect(deleted.verification, verification);

        expect(succeeded.startRendering, throwsStateError);
        expect(deleted.startRendering, throwsStateError);
        expect(deleted.markDeleted, throwsStateError);
      },
    );

    test('failed is terminal, clears output, and distinguishes blocked', () {
      final ExportArtifact failed = _start().fail(failureCode: 'EXP-001');
      expect(failed.state, ExportArtifactState.failed);
      expect(failed.isTerminal, isTrue);
      expect(failed.isPreviewAvailable, isFalse);
      expect(failed.isBlocked, isTrue);
      expect(failed.failureCode, 'EXP-001');
      expect(failed.byteSize, isNull);
      expect(failed.sha256, isNull);
      expect(failed.verification, isNull);

      expect(() => failed.fail(failureCode: 'EXP-002'), throwsStateError);
      expect(failed.markDeleted, throwsStateError);
      expect(() => _succeeded().fail(failureCode: 'EXP-002'), throwsStateError);

      final ExportArtifact renderingFailure = _start().startRendering().fail(
        failureCode: 'EXP-002',
      );
      expect(renderingFailure.isBlocked, isFalse);
      expect(renderingFailure.failureCode, 'EXP-002');

      final ArtifactVerification failedVerification = _verification(
        pageCountMatches: false,
      );
      final ExportArtifact mismatch = _verifying().fail(
        failureCode: 'EXP-002',
        verification: failedVerification,
      );
      expect(mismatch.state, ExportArtifactState.failed);
      expect(mismatch.verification, failedVerification);
      expect(mismatch.isBlocked, isFalse);
    });

    test('blocked failure codes are exactly the preflight block set', () {
      for (final String code in <String>[
        'EXP-001',
        'EXP-003',
        'EXP-004',
        'EXP-005',
        'EXP-006',
      ]) {
        expect(_start().fail(failureCode: code).isBlocked, isTrue);
      }
      for (final String code in <String>['EXP-002', 'SAVE-001']) {
        expect(_start().fail(failureCode: code).isBlocked, isFalse);
      }
      expect(
        exportArtifactBlockedFailureCodes,
        equals(<String>{'EXP-001', 'EXP-003', 'EXP-004', 'EXP-005', 'EXP-006'}),
      );
    });

    test('rejects a verification argument outside verifying', () {
      expect(
        () => _start().fail(
          failureCode: 'EXP-001',
          verification: _verification(),
        ),
        throwsArgumentError,
      );
      expect(
        () => _start().startRendering().fail(
          failureCode: 'EXP-002',
          verification: _verification(),
        ),
        throwsArgumentError,
      );
    });

    test('succeed refuses an incomplete, premature, or malformed success', () {
      final ExportArtifact verifying = _verifying();
      expect(
        () => verifying.succeed(
          byteSize: 4096,
          sha256: _sha256,
          verification: _verification(pageCountMatches: false),
        ),
        throwsArgumentError,
      );
      expect(
        () => verifying.succeed(
          byteSize: 0,
          sha256: _sha256,
          verification: _verification(),
        ),
        throwsArgumentError,
      );
      expect(
        () => verifying.succeed(
          byteSize: -1,
          sha256: _sha256,
          verification: _verification(),
        ),
        throwsArgumentError,
      );
      expect(
        () => verifying.succeed(
          byteSize: 4096,
          sha256: 'not-a-hash',
          verification: _verification(),
        ),
        throwsArgumentError,
      );
      expect(
        () => verifying.succeed(
          byteSize: 4096,
          sha256: _sha256,
          verification: _verification(
            checkedAt: _at().subtract(const Duration(seconds: 1)),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => _start().fail(failureCode: 'not-a-code'),
        throwsArgumentError,
      );
    });

    test('exposes the exact state wire tokens and rejects blocked', () {
      expect(
        ExportArtifactState.values.map(
          (ExportArtifactState state) => state.wireName,
        ),
        equals(<String>[
          'validating',
          'rendering',
          'verifying',
          'succeeded',
          'failed',
          'deleted',
        ]),
      );
      expect(
        ExportArtifactState.fromWire('verifying'),
        ExportArtifactState.verifying,
      );
      expect(
        () => ExportArtifactState.fromWire('blocked'),
        throwsFormatException,
      );
    });
  });

  group('ExportArtifact JSON', () {
    test('round-trips every valid state and preserves unknown fields', () {
      final ExportArtifact start = _start(
        unknownFields: <String, Object?>{'futureArtifact': true},
      );
      final ExportArtifact rendering = start.startRendering();
      final ExportArtifact verifying = rendering.startVerification();
      final ExportArtifact succeeded = verifying.succeed(
        byteSize: 4096,
        sha256: _sha256,
        verification: _verification(),
      );
      final ExportArtifact deleted = succeeded.markDeleted();

      for (final ExportArtifact artifact in <ExportArtifact>[
        start,
        rendering,
        verifying,
        succeeded,
        deleted,
      ]) {
        final Map<String, Object?> json =
            jsonDecode(jsonEncode(artifact.toJson())) as Map<String, Object?>;
        final ExportArtifact restored = ExportArtifact.fromJson(json);
        expect(restored, artifact);
        expect(restored.unknownFields['futureArtifact'], isTrue);
        expect(
          canonicalJsonEncode(restored.toJson()),
          canonicalJsonEncode(artifact.toJson()),
        );
      }
    });

    test('refuses optimistic or inconsistent restored records', () {
      final Map<String, Object?> succeededJson =
          jsonDecode(jsonEncode(_succeeded().toJson())) as Map<String, Object?>;

      final Map<String, Object?> missingVerification =
          Map<String, Object?>.from(succeededJson)..['verification'] = null;
      expect(
        () => ExportArtifact.fromJson(missingVerification),
        throwsFormatException,
      );

      final Map<String, Object?> missingPageCount = Map<String, Object?>.from(
        succeededJson,
      )..['pageCount'] = null;
      expect(
        () => ExportArtifact.fromJson(missingPageCount),
        throwsFormatException,
      );

      final Map<String, Object?> failureWithOutput =
          Map<String, Object?>.from(
              jsonDecode(jsonEncode(_start().toJson())) as Map<String, Object?>,
            )
            ..['state'] = 'failed'
            ..['failureCode'] = 'EXP-002'
            ..['byteSize'] = 4096
            ..['sha256'] = _sha256;
      expect(
        () => ExportArtifact.fromJson(failureWithOutput),
        throwsFormatException,
      );

      final Map<String, Object?> successWithFailureCode =
          Map<String, Object?>.from(succeededJson)..['failureCode'] = 'EXP-002';
      expect(
        () => ExportArtifact.fromJson(successWithFailureCode),
        throwsFormatException,
      );

      final Map<String, Object?> blockedState = Map<String, Object?>.from(
        succeededJson,
      )..['state'] = 'blocked';
      expect(
        () => ExportArtifact.fromJson(blockedState),
        throwsFormatException,
      );

      final Map<String, Object?> badId = Map<String, Object?>.from(
        jsonDecode(jsonEncode(_start().toJson())) as Map<String, Object?>,
      )..['id'] = 'not-a-uuid';
      expect(() => ExportArtifact.fromJson(badId), throwsFormatException);

      final Map<String, Object?> localTimestamp = Map<String, Object?>.from(
        jsonDecode(jsonEncode(_start().toJson())) as Map<String, Object?>,
      )..['createdAt'] = '2026-11-14T12:00:00';
      expect(
        () => ExportArtifact.fromJson(localTimestamp),
        throwsFormatException,
      );
    });
  });
}
