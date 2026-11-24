// T264D A/B/C adaptive-benchmark tests.
//
// This is a dependency-free host test harness, not a package:test suite:
//   dart tools/evaluation/adaptive_benchmark_test.dart
//
// It pins both frozen artifacts byte-for-byte, proves the benchmark reads every
// acceptance threshold out of `acceptanceThresholds` instead of duplicating one,
// checks the declared corpus seam and its dev/holdout/undeclared partition, the
// same-DPI contrast-stretch variant and its frozen pixel budget, the frozen
// metric definitions, the holdout-once discipline both in-process and through the
// CLI, the declared false-accept boundary, and one real A/B/C run over the
// productive stages on a single declared dev page. Every test artifact is
// written to a system temp directory and removed again, so a run leaves nothing
// behind in this tree or in a foreign working directory.
//
// Host-only tooling. No OCR engine, emulator, device, or SIMULATED/EMULATOR
// evidence, and no SC claim.
// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_recognition/src/field_inventory.dart';
import 'package:feldexa_recognition/src/geometry_detector.dart';
import 'package:feldexa_recognition/src/raster.dart';
import 'package:feldexa_recognition/src/structure_comparison.dart';

import 'adaptive_benchmark.dart';
import 'adaptive_trigger.dart' show Verdict;
import 'field_inventory_baseline.dart'
    show
        SyntheticCorpusPage,
        buildSyntheticCorpus,
        syntheticCorpusId,
        syntheticCorpusIdentity;
import 'validate_report.dart' show sha256Hex;

int _checks = 0;
int _failures = 0;

/// SHA-256 of `tools/evaluation/adaptive-policy.v1.json`, as bound by
/// `policyArtifact.sha256` in `tools/evaluation/adaptive-provenance.v1.json`.
const String _pinnedPolicySha256 =
    'eb940399ce1533aaa0a6dba4bba814b311a5041b06daeddc0f9866cacc40e073';

/// SHA-256 of `tools/evaluation/adaptive-provenance.v1.json`.
const String _pinnedProvenanceSha256 =
    '50af51a9eab0def559b1100b2d9b1b290062cc414008d3f13596f174d8146c72';

/// Corpus identity from `tools/evaluation/goldens/field-inventory-baseline.v1.json`
/// (`fixture` object). The benchmark must score exactly this corpus.
const String _pinnedFixtureSha256 =
    '0100e19f2967ba4437ff6649974f766987a1bf3eb22bf033b99f766ddd18d16c';
const String _pinnedCorpusSha256 =
    'c595b7ea7321d081926c277449419921f8b3622fabbd0cc08ee5e40077461f60';
const String _pinnedGroundTruthSha256 =
    '7cfedb615aef3a0326ae2401ca5c5be3e5a3bc650be96f4818c5abcd2dd0cbfe';

void main() {
  final Directory directory = File.fromUri(Platform.script).parent;
  final File policyFile = File.fromUri(
    directory.uri.resolve('adaptive-policy.v1.json'),
  );
  final AdaptiveBenchmarkPolicy benchmark;
  try {
    benchmark = AdaptiveBenchmarkPolicy.load(policyFile);
  } on BenchmarkException catch (error) {
    stderr.writeln('cannot load the frozen benchmark policy: $error');
    exitCode = 1;
    return;
  }

  _group('frozen artifacts', () {
    _check('pins the frozen policy and provenance bytes', () {
      final String policyDigest = sha256Hex(policyFile.readAsBytesSync());
      _expect(
        policyDigest == _pinnedPolicySha256,
        'the frozen policy drifted: $policyDigest',
      );
      final String provenanceDigest = sha256Hex(
        File.fromUri(directory.uri.resolve('adaptive-provenance.v1.json'))
            .readAsBytesSync(),
      );
      _expect(
        provenanceDigest == _pinnedProvenanceSha256,
        'the frozen provenance drifted: $provenanceDigest',
      );
      _expect(benchmark.policySha256 == _pinnedPolicySha256, 'policySha256');
      _expect(
        benchmark.policy.version == '1.0.0',
        'version ${benchmark.policy.version}',
      );
      _expect(
        benchmark.policy.status == 'frozen-before-run',
        'status ${benchmark.policy.status}',
      );
    });

    _check('reads every acceptance outcome out of the frozen artifact', () {
      final Map<String, Object?> document =
          jsonDecode(policyFile.readAsStringSync()) as Map<String, Object?>;
      final Map<String, Object?> acceptance =
          document['acceptanceThresholds']! as Map<String, Object?>;
      final List<String> declared = <String>[
        for (final Object? entry
            in acceptance['requiredOutcomes']! as List<Object?>)
          entry! as String,
      ];
      _expect(
        benchmark.requiredOutcomes.length == declared.length,
        'parsed ${benchmark.requiredOutcomes.length} of ${declared.length} '
        'declared outcomes',
      );
      for (int index = 0; index < declared.length; index++) {
        _expect(
          benchmark.requiredOutcomes[index].text == declared[index],
          'outcome $index text drifted',
        );
      }
      _expect(
        benchmark.noGainClaim == acceptance['noGainClaim'],
        'noGainClaim drifted',
      );
      _expect(
        benchmark.comparisonModes.length ==
            (acceptance['comparisonModes']! as List<Object?>).length,
        'comparisonModes drifted',
      );
      _expect(benchmark.sameInputs, 'sameInputs must be true');
      _expect(!benchmark.holdoutTuning, 'holdoutTuning must be false');
    });

    _check('fails closed on an outcome wording it cannot parse', () {
      final File mutated = _mutatedPolicy('unparsable-outcome', (
        Map<String, Object?> policy,
      ) {
        _outcomes(policy)[0] = 'field recall(C) is at least recall(A)';
      });
      _expectThrows<BenchmarkException>(
        () => AdaptiveBenchmarkPolicy.load(mutated),
      );
    });

    _check('does not duplicate the frozen variant pixel budget', () {
      final RequiredOutcome budget = benchmark.requiredOutcomes.firstWhere(
        (RequiredOutcome outcome) => outcome.text.contains('peak variant'),
      );
      final int frozen = benchmark.policy.bounds.maxVariantPixels;
      final Map<Mode, ModeMetrics> modes = _modes();
      _expect(
        budget
            .evaluate(
              modes,
              RunMetrics(
                peakVariantPixels: frozen,
                peakResidentSetBytes: 1024,
                variantRasterHashes: const <String, String>{},
              ),
            )
            .passed,
        'the parsed threshold must accept the frozen bound $frozen',
      );
      _expect(
        !budget
            .evaluate(
              modes,
              RunMetrics(
                peakVariantPixels: frozen + 1,
                peakResidentSetBytes: 1024,
                variantRasterHashes: const <String, String>{},
              ),
            )
            .passed,
        'the parsed threshold must reject ${frozen + 1}',
      );
    });
  });

  _group('declared corpus seam', () {
    final List<SyntheticCorpusPage> corpus = buildSyntheticCorpus();

    _check('draws the declared corpus with the frozen identity', () {
      _expect(corpus.length == 12, 'page count ${corpus.length}');
      final Map<String, String> identity = syntheticCorpusIdentity(corpus);
      _expect(
        identity['fixtureSha256'] == _pinnedFixtureSha256,
        'fixtureSha256 ${identity['fixtureSha256']}',
      );
      _expect(
        identity['corpusSha256'] == _pinnedCorpusSha256,
        'corpusSha256 ${identity['corpusSha256']}',
      );
      _expect(
        identity['groundTruthSha256'] == _pinnedGroundTruthSha256,
        'groundTruthSha256 ${identity['groundTruthSha256']}',
      );
      for (final SyntheticCorpusPage page in corpus) {
        _expect(
          page.raster.width == 1654 && page.raster.height == 2339,
          '${page.id} raster ${page.raster.width}x${page.raster.height}',
        );
        _expect(
          page.rasterSha256.length == 64,
          '${page.id} has no raster hash',
        );
      }
      _expect(
        corpus.fold<int>(
              0,
              (int sum, SyntheticCorpusPage page) => sum + page.fields.length,
            ) ==
            43,
        'declared field total drifted',
      );
      _expect(
        corpus
            .firstWhere(
              (SyntheticCorpusPage page) => page.id == 'furniture-only',
            )
            .fields
            .isEmpty,
        'furniture-only is a known zero-field page',
      );
    });

    _check('partitions the corpus into dev, holdout and undeclared pages', () {
      final CorpusPartition partition = partitionCorpus(
        policy: benchmark.policy,
        pages: corpus,
      );
      _expect(
        _ids(partition.dev).join(',') == benchmark.policy.devPages.join(','),
        'dev ${_ids(partition.dev)}',
      );
      _expect(
        _ids(partition.holdout).join(',') ==
            benchmark.policy.holdoutPages.join(','),
        'holdout ${_ids(partition.holdout)}',
      );
      _expect(
        _ids(partition.undeclared).join(',') ==
            'numeric-variants,multiline-area',
        'undeclared ${_ids(partition.undeclared)}',
      );
      for (final SyntheticCorpusPage page in partition.undeclared) {
        _expect(
          partition.undeclaredReasons.containsKey(page.id),
          '${page.id} has no undeclared reason',
        );
        _expect(!partition.scored.contains(page), '${page.id} is scored');
      }
      _expect(
        partition.scored.length == 10,
        'scored ${partition.scored.length}',
      );
    });

    _check('refuses a corpus that is not the declared one', () {
      checkCorpusId(declared: syntheticCorpusId, drawn: syntheticCorpusId);
      _expectThrows<BenchmarkException>(
        () =>
            checkCorpusId(declared: 'another-corpus', drawn: syntheticCorpusId),
      );
    });

    _check('refuses a policy page the corpus does not declare', () {
      final File mutated = _mutatedPolicy('unknown-dev-page', (
        Map<String, Object?> policy,
      ) {
        _corpusAndHoldout(policy)['devPages'] = <String>[
          'clean-text',
          'no-such-page',
        ];
      });
      _expectThrows<BenchmarkException>(
        () => partitionCorpus(
          policy: AdaptiveBenchmarkPolicy.load(mutated).policy,
          pages: corpus,
        ),
      );
    });
  });

  _group('same-DPI variant', () {
    _check('stretches p05/p95 onto 0/255 and keeps the raster grid', () {
      final GrayRaster source = GrayRaster.fromGrayBytes(
        width: 4,
        height: 1,
        bytes: <int>[10, 10, 200, 200],
      );
      final VariantRaster variant = renderContrastStretch(
        source,
        p05Luminance: 10,
        p95Luminance: 200,
      );
      _expect(variant.variantId == 'contrastStretch', 'variantId');
      _expect(variant.widthPx == 4 && variant.heightPx == 1, 'grid');
      _expect(
        variant.raster.pixels.toList().join(',') == '0,0,255,255',
        'stretched bytes ${variant.raster.pixels.toList()}',
      );
      _expect(!variant.identity, 'a real stretch is not identity');
    });

    _check('stretch is deterministic and identity on a full-range raster', () {
      final GrayRaster source = GrayRaster.fromGrayBytes(
        width: 3,
        height: 1,
        bytes: <int>[0, 128, 255],
      );
      final VariantRaster first = renderContrastStretch(
        source,
        p05Luminance: 0,
        p95Luminance: 255,
      );
      final VariantRaster second = renderContrastStretch(
        source,
        p05Luminance: 0,
        p95Luminance: 255,
      );
      _expect(first.identity, 'a full-range stretch is identity');
      _expect(
        first.rasterSha256 == second.rasterSha256,
        'the variant is not deterministic',
      );
      _expect(
        first.raster.pixels.toList().join(',') == '0,128,255',
        'identity stretch changed bytes',
      );
    });

    _check('refuses a variant raster above the frozen pixel budget', () {
      _expectThrows<VariantBudgetException>(
        () => checkVariantPixelBudget(
          widthPx: 4000,
          heightPx: 3000,
          maxVariantPixels: 8000000,
        ),
      );
      checkVariantPixelBudget(
        widthPx: 1654,
        heightPx: 2339,
        maxVariantPixels: 8000000,
      );
    });
  });

  _group('frozen metric definitions', () {
    _check('precision/recall/F1 and IoU follow the frozen definitions', () {
      final List<ExpectedField> expected = <ExpectedField>[
        ExpectedField(
          pageIndex: 0,
          rect: DisplayRect(x: 100, y: 100, width: 200, height: 18),
          kind: FieldInventoryKind.text,
          labelText: 'Name',
          sourceId: 'a',
        ),
        ExpectedField(
          pageIndex: 0,
          rect: DisplayRect(x: 100, y: 200, width: 200, height: 18),
          kind: FieldInventoryKind.text,
          labelText: 'Ort',
          sourceId: 'b',
        ),
      ];
      final List<ObservedField> observed = <ObservedField>[
        ObservedField(
          pageIndex: 0,
          rect: DisplayRect(x: 100, y: 100, width: 200, height: 18),
          kind: FieldInventoryKind.text,
          labelText: 'Name',
        ),
        ObservedField(
          pageIndex: 0,
          rect: DisplayRect(x: 400, y: 400, width: 40, height: 18),
          kind: FieldInventoryKind.text,
        ),
      ];
      final StructureComparisonResult result = StructureComparison.compare(
        expected: expected,
        observed: observed,
        groundTruthPages: <int>{0},
      );
      final StructureMetrics metrics = StructureMetrics.fromComparison(
        expected: expected,
        observed: observed,
        result: result,
      );
      _expect(metrics.expected == 2, 'expected ${metrics.expected}');
      _expect(metrics.matched == 1, 'matched ${metrics.matched}');
      _expect(metrics.extra == 1, 'extra ${metrics.extra}');
      _expect(metrics.missing == 1, 'missing ${metrics.missing}');
      _expectClose(metrics.precision, 0.5, 'precision');
      _expectClose(metrics.recall, 0.5, 'recall');
      _expectClose(metrics.f1, 0.5, 'f1');
      _expectClose(metrics.meanMatchedIou, 1.0, 'meanMatchedIou');
      _expectClose(metrics.typeAccuracy, 1.0, 'typeAccuracy');
      _expectClose(metrics.labelAccuracy, 0.5, 'labelAccuracy');
      _expectClose(metrics.reviewRate, 0.5, 'reviewRate');
      _expect(metrics.reviewNeeded == 1, 'reviewNeeded');
    });

    _check('review rate counts every observation a reviewer must look at', () {
      final List<ExpectedField> expected = <ExpectedField>[
        ExpectedField(
          pageIndex: 0,
          rect: DisplayRect(x: 100, y: 100, width: 200, height: 18),
          kind: FieldInventoryKind.text,
          labelText: 'Name',
          sourceId: 'a',
        ),
      ];
      final List<ObservedField> observed = <ObservedField>[
        ObservedField(
          pageIndex: 0,
          rect: DisplayRect(x: 100, y: 100, width: 200, height: 18),
          kind: FieldInventoryKind.number,
          labelText: 'Name',
        ),
        ObservedField(
          pageIndex: 0,
          rect: DisplayRect(x: 400, y: 400, width: 40, height: 18),
          kind: FieldInventoryKind.text,
        ),
      ];
      final StructureComparisonResult result = StructureComparison.compare(
        expected: expected,
        observed: observed,
        groundTruthPages: <int>{0},
      );
      final StructureMetrics metrics = StructureMetrics.fromComparison(
        expected: expected,
        observed: observed,
        result: result,
      );
      _expect(metrics.extra == 1, 'extra');
      _expect(metrics.typeMismatched == 1, 'typeMismatched');
      _expect(
        metrics.reviewNeeded == 2,
        'reviewNeeded ${metrics.reviewNeeded}',
      );
      _expectClose(metrics.reviewRate, 1.0, 'reviewRate');
      _expectClose(metrics.typeAccuracy, 0.0, 'typeAccuracy');
    });

    _check('a zero false-accept count is not vacuous', () {
      final List<ExpectedField> expected = <ExpectedField>[
        ExpectedField(
          pageIndex: 0,
          rect: DisplayRect(x: 100, y: 100, width: 200, height: 18),
          kind: FieldInventoryKind.text,
          sourceId: 'a',
        ),
      ];
      final List<ObservedField> observed = <ObservedField>[
        ObservedField(
          pageIndex: 0,
          rect: DisplayRect(x: 100, y: 100, width: 200, height: 18),
          kind: FieldInventoryKind.number,
        ),
        ObservedField(
          pageIndex: 0,
          rect: DisplayRect(x: 400, y: 400, width: 40, height: 18),
          kind: FieldInventoryKind.text,
        ),
      ];
      final StructureComparisonResult result = StructureComparison.compare(
        expected: expected,
        observed: observed,
        groundTruthPages: <int>{0},
      );
      final StructureMetrics metrics = StructureMetrics.fromComparison(
        expected: expected,
        observed: observed,
        result: result,
      );
      _expect(metrics.autoConfirmed == 0, 'nothing is auto-confirmed');
      _expect(
        metrics.falseAccepts == 0,
        'falseAccepts ${metrics.falseAccepts}',
      );
      _expect(
        metrics.wouldBeFalseAccepts == 2,
        'the counter must be able to see the two defects: '
        '${metrics.wouldBeFalseAccepts}',
      );
    });

    _check('reports nearest-rank percentiles', () {
      final List<int> values = <int>[10, 20, 30, 40];
      _expect(percentileOfSorted(values, 0.5) == 20, 'p50');
      _expect(percentileOfSorted(values, 0.95) == 40, 'p95');
      _expect(percentileOfSorted(values, 0.0) == 10, 'p0');
      _expect(percentileOfSorted(const <int>[], 0.5) == 0, 'empty');
    });
  });

  _group('acceptance outcomes', () {
    _check('evaluates every declared outcome to one PASS/FAIL verdict', () {
      final Map<Mode, ModeMetrics> modes = _modes();
      for (final RequiredOutcome outcome in benchmark.requiredOutcomes) {
        final OutcomeVerdict verdict = outcome.evaluate(
          modes,
          RunMetrics(
            peakVariantPixels: 1000,
            peakResidentSetBytes: 1024,
            variantRasterHashes: const <String, String>{},
          ),
        );
        _expect(verdict.text == outcome.text, 'verdict text drifted');
        _expect(
          verdict.detail.trim().isNotEmpty,
          '${outcome.text} has no measured detail',
        );
      }
      _expect(
        benchmark.requiredOutcomes.length == 12,
        'outcome count ${benchmark.requiredOutcomes.length}',
      );
    });

    _check('rejects one false accept under a declared zero limit', () {
      ModeMetrics modeMetrics(Mode mode, int falseAccepts) => ModeMetrics(
        mode: mode,
        pageCount: 1,
        passes: 1,
        expected: 2,
        matched: 1,
        observed: 2,
        extra: 1,
        missing: 1,
        duplicateUnmatched: 0,
        kindMatched: 1,
        labelledExpected: 2,
        labelsAgree: 1,
        meanMatchedIou: 0.9,
        reviewNeeded: 1,
        autoConfirmed: 0,
        falseAccepts: falseAccepts,
        latencyMillis: <int>[100],
      );
      final RequiredOutcome clause = benchmark.requiredOutcomes.firstWhere(
        (RequiredOutcome outcome) =>
            outcome.text.toLowerCase().startsWith('false accepts'),
      );
      final RunMetrics runMetrics = RunMetrics(
        peakVariantPixels: 1000,
        peakResidentSetBytes: 1024,
        variantRasterHashes: const <String, String>{},
      );

      _expect(
        clause.evaluate(<Mode, ModeMetrics>{
          Mode.a: modeMetrics(Mode.a, 0),
          Mode.b: modeMetrics(Mode.b, 0),
          Mode.c: modeMetrics(Mode.c, 0),
        }, runMetrics).passed,
        'zero false accepts must satisfy the declared clause: ${clause.text}',
      );
      // The declared limit is a hard boundary: a single false accept in any one
      // mode fails the whole run.
      for (final Mode mode in Mode.values) {
        final OutcomeVerdict verdict = clause.evaluate(
          <Mode, ModeMetrics>{
            Mode.a: modeMetrics(Mode.a, 0),
            Mode.b: modeMetrics(Mode.b, 0),
            Mode.c: modeMetrics(Mode.c, 0),
          }..[mode] = modeMetrics(mode, 1),
          runMetrics,
        );
        _expect(
          !verdict.passed,
          'one false accept in ${mode.name} must fail the clause: '
          '${verdict.detail}',
        );
      }
    });

    _check('an unchanged C result is no gain and keeps the baseline', () {
      final Map<Mode, ModeMetrics> identical = <Mode, ModeMetrics>{
        Mode.a: _metrics(mode: Mode.a),
        Mode.b: _metrics(mode: Mode.b, passes: 2),
        Mode.c: _metrics(mode: Mode.c),
      };
      _expect(
        isNoGain(identical),
        'identical C/A metrics must be reported as no gain',
      );
      final Map<Mode, ModeMetrics> improved = <Mode, ModeMetrics>{
        Mode.a: _metrics(mode: Mode.a),
        Mode.b: _metrics(mode: Mode.b, passes: 2),
        Mode.c: _metrics(mode: Mode.c, matched: 2),
      };
      _expect(!isNoGain(improved), 'a strictly better recall in C is a gain');
    });
  });

  _group('holdout discipline', () {
    _check('refuses a second holdout scoring for the same policy', () {
      final Directory scratch = _scratchDir('holdout-ledger');
      final File ledger = File('${scratch.path}/ledger.json');
      final HoldoutLedger empty = HoldoutLedger.read(ledger);
      _expect(
        !empty.hasScored(_pinnedPolicySha256),
        'a fresh ledger has no holdout scoring',
      );
      expectHoldoutNotScored(ledger: empty, policySha256: _pinnedPolicySha256);
      final HoldoutLedger recorded = empty.record(
        policySha256: _pinnedPolicySha256,
        runId: 'test-run',
        atUtc: DateTime.utc(2026, 11, 24, 12),
      );
      recorded.write(ledger);
      final HoldoutLedger reloaded = HoldoutLedger.read(ledger);
      _expect(
        reloaded.hasScored(_pinnedPolicySha256),
        'the recorded scoring is not readable back',
      );
      _expectThrows<HoldoutAlreadyScoredException>(
        () => expectHoldoutNotScored(
          ledger: reloaded,
          policySha256: _pinnedPolicySha256,
        ),
      );
    });

    _check('the CLI refuses before it analyses a page of a scored holdout', () {
      final Directory scratch = Directory.systemTemp.createTempSync(
        't264d-guard',
      );
      try {
        final File ledger = File('${scratch.path}/ledger.json');
        // Score the *current* policy, whatever its version, so this check pins
        // the wiring and not the frozen SHA.
        HoldoutLedger.read(File('${scratch.path}/none.json'))
            .record(
              policySha256: benchmark.policySha256,
              runId: 'test',
              atUtc: DateTime.utc(2026, 11, 24),
            )
            .write(ledger);
        final List<int> ledgerBefore = ledger.readAsBytesSync();
        final File output = File('${scratch.path}/again.json');
        final String cli = File.fromUri(
          File.fromUri(Platform.script).parent.uri
              .resolve('adaptive_benchmark.dart'),
        ).path;

        final ProcessResult result = Process.runSync(
          Platform.resolvedExecutable,
          <String>[
            'run',
            cli,
            '--output',
            output.path,
            '--score',
            'holdout',
            '--holdout-ledger',
            ledger.path,
          ],
          workingDirectory: Directory.current.path,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );

        _expect(
          result.exitCode == 4,
          'the CLI must refuse with exit 4, got ${result.exitCode}: '
          '${result.stdout}${result.stderr}',
        );
        _expect(
          !output.existsSync(),
          'a refused holdout scoring must write no run artifact',
        );
        _expect(
          '${result.stdout}${result.stderr}'.contains(
            'holdout was already scored',
          ),
          'the refusal must name the scored holdout: '
          '${result.stdout}${result.stderr}',
        );
        _expect(
          _sameBytes(ledgerBefore, ledger.readAsBytesSync()),
          'a refused scoring must not touch the ledger',
        );
      } finally {
        if (scratch.existsSync()) {
          scratch.deleteSync(recursive: true);
        }
      }
    });
  });

  _group('test hygiene', () {
    _check('the scratch directory is removed again', () {
      final File mutated = _mutatedPolicy('cleanup-probe', (
        Map<String, Object?> policy,
      ) {
        _acceptance(policy)['noGainClaim'] = true;
      });
      final Directory scratch = _scratch();
      _expect(
        mutated.existsSync(),
        'the mutated artifact exists while running',
      );
      _expect(
        mutated.path.startsWith(Directory.systemTemp.path),
        'the mutated artifact must live under ${Directory.systemTemp.path}: '
        '${mutated.path}',
      );
      _expect(
        !mutated.path.contains('.dart_tool/adaptive_benchmark_test'),
        'no scratch directory under .dart_tool: ${mutated.path}',
      );
      _expect(scratch.existsSync(), 'the scratch root exists while running');
      _deleteScratch();
      _expect(!scratch.existsSync(), 'the scratch root is deleted: $scratch');
      _expect(!mutated.existsSync(), 'its artifacts are gone: ${mutated.path}');
    });
  });

  _group('one declared dev page, end to end', () {
    _check('runs A/B/C over the productive stages on the same source', () {
      final List<SyntheticCorpusPage> corpus = buildSyntheticCorpus();
      final SyntheticCorpusPage page = corpus.firstWhere(
        (SyntheticCorpusPage candidate) => candidate.id == 'clean-text',
      );
      final BenchmarkRun run = runBenchmark(
        benchmark: benchmark,
        pages: <SyntheticCorpusPage>[page],
        scoreSet: ScoreSet.dev,
      );
      _expect(run.pages.length == 1, 'page count');
      final PageRun pageRun = run.pages.single;
      _expect(pageRun.pass1.passNumber == 1, 'pass 1');
      _expect(pageRun.pass2.passNumber == 2, 'pass 2');
      _expect(
        pageRun.pass1.sourceRasterSha256 == page.rasterSha256,
        'pass 1 must analyse the declared raster',
      );
      _expect(
        pageRun.pass2.sourceRasterSha256 == page.rasterSha256,
        'pass 2 must derive from the same declared raster',
      );
      if (pageRun.variantIdentity) {
        _expect(
          pageRun.pass2.inputRasterSha256 == page.rasterSha256,
          'an identity stretch must keep the raster bytes',
        );
      } else {
        _expect(
          pageRun.pass2.inputRasterSha256 != page.rasterSha256,
          'a real stretch must change the raster bytes',
        );
      }
      _expect(
        pageRun.pass2.variantId == 'contrastStretch',
        'variant ${pageRun.pass2.variantId}',
      );
      _expect(
        run.byMode[Mode.a]!.passes == 1,
        'A passes ${run.byMode[Mode.a]!.passes}',
      );
      _expect(
        run.byMode[Mode.b]!.passes == 2,
        'B passes ${run.byMode[Mode.b]!.passes}',
      );
      _expect(
        run.byMode[Mode.c]!.passes ==
            1 + (pageRun.decision.verdict == Verdict.secondPass ? 1 : 0),
        'C passes ${run.byMode[Mode.c]!.passes}',
      );
      for (final Mode mode in Mode.values) {
        _expect(
          run.byMode[mode]!.expected == page.fields.length,
          '$mode expected ${run.byMode[mode]!.expected}',
        );
        _expect(
          run.byMode[mode]!.falseAccepts == 0,
          '$mode false accepts ${run.byMode[mode]!.falseAccepts}',
        );
      }
      _expect(
        run.outcomes.length == benchmark.requiredOutcomes.length,
        'gate outcomes ${run.outcomes.length}',
      );
      _expect(
        run.runMetrics.peakVariantPixels > 0,
        'the run must report the measured variant pixels',
      );
      _expect(
        run.runMetrics.peakResidentSetBytes > 0,
        'the run must report the measured peak RSS',
      );
    });
  });

  _deleteScratch();
  stdout.writeln('\n$_checks checks, $_failures failure(s)');
  if (_failures > 0) {
    exitCode = 1;
  }
}

// ---------------------------------------------------------------------------
// Fixtures and helpers
// ---------------------------------------------------------------------------

List<String> _ids(List<SyntheticCorpusPage> pages) => <String>[
  for (final SyntheticCorpusPage page in pages) page.id,
];

Map<Mode, ModeMetrics> _modes() => <Mode, ModeMetrics>{
  Mode.a: _metrics(mode: Mode.a),
  Mode.b: _metrics(mode: Mode.b, passes: 2),
  Mode.c: _metrics(mode: Mode.c, passes: 1),
};

ModeMetrics _metrics({
  required Mode mode,
  int passes = 1,
  int matched = 1,
  int latencyMs = 100,
}) => ModeMetrics(
  mode: mode,
  pageCount: 1,
  passes: passes,
  expected: 2,
  matched: matched,
  observed: 2,
  extra: matched == 2 ? 0 : 1,
  missing: 2 - matched,
  duplicateUnmatched: 0,
  kindMatched: matched,
  labelledExpected: 2,
  labelsAgree: 1,
  meanMatchedIou: 0.9,
  reviewNeeded: matched == 2 ? 0 : 1,
  autoConfirmed: 0,
  falseAccepts: 0,
  latencyMillis: <int>[latencyMs],
);

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

void _expectClose(double actual, double expected, String message) {
  if ((actual - expected).abs() > 1e-9) {
    throw StateError('$message: $actual != $expected');
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _expectThrows<T extends Object>(void Function() body) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T');
}

List<Object?> _outcomes(Map<String, Object?> policy) =>
    (_acceptance(policy)['requiredOutcomes']! as List<Object?>);

Map<String, Object?> _acceptance(Map<String, Object?> policy) =>
    policy['acceptanceThresholds']! as Map<String, Object?>;

Map<String, Object?> _corpusAndHoldout(Map<String, Object?> policy) =>
    policy['corpusAndHoldout']! as Map<String, Object?>;

/// Scratch root for the test artifact copies, created on first use under the
/// system temp directory so a run from any working directory leaves nothing in
/// the tree. [main] deletes it before it prints its summary.
Directory? _scratchRoot;

Directory _scratch() => _scratchRoot ??= Directory.systemTemp.createTempSync(
  'adaptive_benchmark_test.',
);

/// The per-artifact directory inside the scratch root, recreated per call.
Directory _scratchDir(String name) {
  final Directory target = Directory('${_scratch().path}/$name');
  if (target.existsSync()) {
    target.deleteSync(recursive: true);
  }
  target.createSync(recursive: true);
  return target;
}

/// Deletes the scratch root; the next [_scratch] call creates a fresh one.
void _deleteScratch() {
  final Directory? scratch = _scratchRoot;
  _scratchRoot = null;
  if (scratch != null && scratch.existsSync()) {
    scratch.deleteSync(recursive: true);
  }
}

/// Writes a mutated copy of both frozen artifacts so a load sees the change.
File _mutatedPolicy(
  String name,
  void Function(Map<String, Object?> policy) mutate,
) {
  final Directory source = File.fromUri(Platform.script).parent;
  final Directory target = _scratchDir(name);
  File.fromUri(source.uri.resolve('adaptive-provenance.v1.json'))
      .copySync('${target.path}/adaptive-provenance.v1.json');
  final Map<String, Object?> policy = jsonDecode(
    File.fromUri(source.uri.resolve('adaptive-policy.v1.json'))
        .readAsStringSync(),
  ) as Map<String, Object?>;
  mutate(policy);
  final File mutated = File('${target.path}/adaptive-policy.v1.json');
  mutated.writeAsStringSync(jsonEncode(policy));
  return mutated;
}
