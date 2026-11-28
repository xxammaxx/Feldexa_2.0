// T134 numeric accessibility audit on the real Android runtime (SC-015;
// FR-092/FR-093; CHK022).
//
// Evidence class: `EMULATOR` only. The test runs the production `FeldexaApp`
// root on the exclusively allocated `emulator-5554`; the debug-only
// `de.feldexa/test.import` seam arms the committed synthetic `sf-001.pdf`, the
// production import action performs the real encrypted staging, preflight, and
// verified commit, and the audit measures the start surface and the resulting
// editor surface. No adapter, renderer, store, or route is replaced.
//
// Numeric thresholds (CHK022, not "applicable minimum"):
//   * text scale: the audit runs with `textScaleFactor = 2.0` (200 %) and
//     asserts `MediaQuery.textScaler.scale(10) == 20.0` before measuring;
//   * contrast: every visible `Text` run must reach >= 4.5:1 for normal text
//     and >= 3:1 for large text (>= 18 px, or >= 14 px bold); the foreground
//     is composited over the nearest opaque ancestor background;
//   * touch targets: every primary control (`ButtonStyleButton`, `IconButton`,
//     tappable `InkWell` row) must measure at least 48 x 48 logical pixels and
//     be present in the semantics tree (screen-reader reachability);
//   * 200 % layout: no Flutter overflow/exception may be raised while the
//     start and editor surfaces are laid out at 200 % text.
//
// Determinism: the fixture bytes are pinned by SHA-256, the thresholds are
// constants, and every measurement is read from the laid-out widget tree.
// There are no screenshot claims in this test. The host driver only stages the
// fixture:
//
//   adb -s emulator-5554 push tools/corpus/synthetic/sf-001.pdf \
//     /data/local/tmp/t134-fixtures/sf-001.pdf
//   flutter test integration_test/accessibility_audit_test.dart \
//     -d emulator-5554
//
// Privacy: markers carry phase names, counts, and ratios only; no document
// text, path, URI, title, or entered value is printed.

import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:feldexa_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/accessibility_thresholds.dart';

const String _fixtureDir = '/data/local/tmp/t134-fixtures';
const String _fixtureName = 'sf-001.pdf';
const String _fixtureSha256 =
    '22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038';
const int _fixtureSizeBytes = 5956;
const String _fixtureDisplayName = 't134-a11y.pdf';

const double _minTargetDp = 48.0;
const double _scaleFactor = 2.0;

const ValueKey<String> _startScreenKey = ValueKey<String>('start-screen');
const ValueKey<String> _editorScreenKey = ValueKey<String>('editor-screen');
const ValueKey<String> _importActionKey = ValueKey<String>('import-action');

const MethodChannel _testHooks = MethodChannel('de.feldexa/test.import');

void _marker(String phase) {
  debugPrint('T134_$phase');
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

/// One audited text run.
final class _TextSample {
  _TextSample(this.text, this.fontSize, this.bold, this.ratio, this.required);

  final String text;
  final double fontSize;
  final bool bold;
  final double ratio;
  final double required;
}

/// One audited primary control.
final class _ControlSample {
  _ControlSample(this.kind, this.size, this.hasSemantics);

  final String kind;
  final Size size;
  final bool hasSemantics;
}

Color _compositeOver(Color foreground, Color background) {
  final double alpha = foreground.a;
  if (alpha >= 1.0) {
    return foreground;
  }
  final double r = foreground.r * alpha + background.r * (1 - alpha);
  final double g = foreground.g * alpha + background.g * (1 - alpha);
  final double b = foreground.b * alpha + background.b * (1 - alpha);
  return Color.from(alpha: 1, red: r, green: g, blue: b);
}

/// The nearest opaque ancestor background behind [element].
Color _backgroundBehind(BuildContext context, Element element) {
  final ThemeData theme = Theme.of(context);
  Color? found;
  element.visitAncestorElements((Element ancestor) {
    final Widget widget = ancestor.widget;
    Color? candidate;
    if (widget is Material) {
      candidate = widget.color;
    } else if (widget is ColoredBox) {
      candidate = widget.color;
    } else if (widget is DecoratedBox && widget.decoration is BoxDecoration) {
      candidate = (widget.decoration as BoxDecoration).color;
    } else if (widget is Scaffold) {
      candidate = widget.backgroundColor ?? theme.scaffoldBackgroundColor;
    } else if (widget is Card) {
      candidate = widget.color ?? theme.cardColor;
    }
    if (candidate != null && candidate.a > 0) {
      found = candidate;
      return false;
    }
    return true;
  });
  return found ?? theme.scaffoldBackgroundColor;
}

bool _isVisible(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) {
    return false;
  }
  final Rect rect = tester.getRect(finder);
  final Size view = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.width > 0 && rect.height > 0 && rect.overlaps(Offset.zero & view);
}

List<_TextSample> _auditText(WidgetTester tester) {
  final List<_TextSample> samples = <_TextSample>[];
  final Finder texts = find.byType(Text);
  for (int i = 0; i < texts.evaluate().length; i++) {
    final Finder finder = texts.at(i);
    final Text widget = tester.widget<Text>(finder);
    final String data = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (data.trim().isEmpty || !_isVisible(tester, finder)) {
      continue;
    }
    final BuildContext context = tester.element(finder);
    final DefaultTextStyle defaultStyle = DefaultTextStyle.of(context);
    final TextStyle style = defaultStyle.style.merge(widget.style);
    final ThemeData theme = Theme.of(context);
    final Color foreground =
        style.color ??
        theme.textTheme.bodyMedium?.color ??
        theme.colorScheme.onSurface;
    final Color background = _backgroundBehind(context, tester.element(finder));
    final double fontSize = style.fontSize ?? 14.0;
    final FontWeight weight = style.fontWeight ?? FontWeight.normal;
    final bool bold = weight.value >= FontWeight.w600.value;
    // WCAG large text is an unscaled property of the style (18 px, or 14 px
    // bold). Scaling first would make every 200 % run large and never apply
    // the 4.5:1 normal-text threshold.
    final bool large = isLargeText(fontSize, weight);
    final double required = requiredContrast(fontSize, weight);
    final Color flattened = _compositeOver(foreground, background);
    final double ratio = contrastRatio(flattened, background);
    samples.add(_TextSample(data, fontSize, bold, ratio, required));
    if (large) {
      _marker(
        'LARGE:$fontSize:${bold ? 'bold' : 'regular'}:'
        '${ratio.toStringAsFixed(3)}',
      );
    }
  }
  return samples;
}

bool _insideButton(WidgetTester tester, Finder finder) {
  bool inside = false;
  tester.element(finder).visitAncestorElements((Element ancestor) {
    final Widget widget = ancestor.widget;
    if (widget is ButtonStyleButton || widget is IconButton) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

/// Whether the control owns a labeled semantics node.
///
/// `tester.getSemantics` walks up to the first unmerged ancestor; the node is
/// only accepted when its size is bounded by the control's own hit target
/// (+56 px tolerance for merged children). That rejects the route/root node
/// (which is screen-sized) and a control whose semantics were removed, and
/// requires a label/tooltip/value plus a tap action for enabled controls.
bool _controlHasOwnSemantics(WidgetTester tester, Finder finder) {
  final Widget controlWidget = tester.widget(finder);
  bool enabled;
  if (controlWidget is IconButton) {
    enabled = controlWidget.onPressed != null;
  } else if (controlWidget is ButtonStyleButton) {
    enabled = controlWidget.onPressed != null;
  } else if (controlWidget is InkWell) {
    enabled = controlWidget.onTap != null;
  } else {
    enabled = true;
  }
  final SemanticsNode node;
  try {
    node = tester.getSemantics(finder);
  } on StateError {
    return false;
  } on FlutterError {
    return false;
  }
  final Size control = tester.getSize(finder);
  final Size nodeSize = node.rect.size;
  final bool sizeBound =
      nodeSize.width <= control.width + 56.0 &&
      nodeSize.height <= control.height + 56.0;
  final SemanticsData data = node.getSemanticsData();
  final bool labeled =
      data.label.trim().isNotEmpty ||
      data.tooltip.trim().isNotEmpty ||
      data.value.trim().isNotEmpty;
  return sizeBound &&
      labeled &&
      (!enabled || data.hasAction(SemanticsAction.tap));
}

List<_ControlSample> _auditControls(WidgetTester tester) {
  final List<_ControlSample> samples = <_ControlSample>[];
  final Set<RenderObject> measured = <RenderObject>{};
  final Finder controls = find.byWidgetPredicate(
    (Widget widget) =>
        widget is ButtonStyleButton ||
        widget is IconButton ||
        (widget is InkWell && widget.onTap != null),
  );
  for (int i = 0; i < controls.evaluate().length; i++) {
    final Finder finder = controls.at(i);
    if (!_isVisible(tester, finder)) {
      continue;
    }
    if (tester.widget(finder) is InkWell && _insideButton(tester, finder)) {
      // The button already exposes the same tap target; do not count its
      // internal InkWell a second time.
      continue;
    }
    final RenderObject? renderObject = tester
        .element(finder)
        .findRenderObject();
    if (renderObject != null && !measured.add(renderObject)) {
      // M3 IconButton and its internal ButtonStyleButton share one render
      // object; count the hit target once.
      continue;
    }
    final Size size = tester.getSize(finder);
    final Widget widget = tester.widget(finder);
    final bool hasSemantics = _controlHasOwnSemantics(tester, finder);
    final String kind = widget is IconButton
        ? 'IconButton'
        : widget is ButtonStyleButton
        ? 'Button'
        : 'InkWell';
    samples.add(_ControlSample(kind, size, hasSemantics));
  }
  return samples;
}

void _reportText(List<_TextSample> samples, String surface) {
  expect(samples, isNotEmpty, reason: '$surface has no visible text');
  double minRatio = double.infinity;
  _TextSample? worst;
  int failures = 0;
  for (final _TextSample sample in samples) {
    if (sample.ratio < minRatio) {
      minRatio = sample.ratio;
      worst = sample;
    }
    if (sample.ratio + 1e-9 < sample.required) {
      failures++;
      debugPrint(
        'T134_CONTRAST_FAIL:$surface:ratio=${sample.ratio.toStringAsFixed(3)}:'
        'required=${sample.required.toStringAsFixed(1)}:'
        'size=${sample.fontSize.toStringAsFixed(1)}:bold=${sample.bold}',
      );
    }
  }
  _marker(
    'TEXT:$surface:count=${samples.length}:'
    'minContrast=${minRatio.toStringAsFixed(3)}:failures=$failures',
  );
  expect(
    failures,
    0,
    reason:
        '$surface: $failures/${samples.length} text runs are below their '
        'contrast threshold (worst ${minRatio.toStringAsFixed(3)}:1, '
        'required ${worst?.required.toStringAsFixed(1) ?? '-'}:1)',
  );
}

void _reportControls(List<_ControlSample> samples, String surface) {
  expect(samples, isNotEmpty, reason: '$surface has no primary controls');
  double minEdge = double.infinity;
  int tooSmall = 0;
  int withoutSemantics = 0;
  for (final _ControlSample sample in samples) {
    final double edge = math.min(sample.size.width, sample.size.height);
    if (edge < minEdge) {
      minEdge = edge;
    }
    if (edge + 1e-9 < _minTargetDp) {
      tooSmall++;
      debugPrint(
        'T134_TARGET_FAIL:$surface:${sample.kind}:'
        'w=${sample.size.width.toStringAsFixed(2)}:'
        'h=${sample.size.height.toStringAsFixed(2)}',
      );
    }
    if (!sample.hasSemantics) {
      withoutSemantics++;
      debugPrint('T134_SEMANTICS_FAIL:$surface:${sample.kind}');
    }
  }
  _marker(
    'CONTROLS:$surface:count=${samples.length}:'
    'minEdge=${minEdge.toStringAsFixed(2)}:tooSmall=$tooSmall:'
    'noSemantics=$withoutSemantics',
  );
  expect(
    tooSmall,
    0,
    reason:
        '$surface: $tooSmall/${samples.length} primary controls are below '
        '${_minTargetDp.toStringAsFixed(0)} dp (smallest edge '
        '${minEdge.toStringAsFixed(2)} dp)',
  );
  expect(
    withoutSemantics,
    0,
    reason:
        '$surface: $withoutSemantics/${samples.length} primary controls are '
        'absent from the semantics tree',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'numeric accessibility audit at 200 percent text on start and editor',
    (WidgetTester tester) async {
      expect(Platform.isAndroid, isTrue, reason: 'EMULATOR lane only');
      await _armFixture();

      tester.platformDispatcher.textScaleFactorTestValue = _scaleFactor;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final SemanticsHandle semantics = tester.ensureSemantics();

      // Production root, same widget `main()` builds. The startup sweep is a
      // storage concern and is not part of this audit.
      await tester.pumpWidget(const app.FeldexaApp());
      await _pumpUntil(
        tester,
        () => find.byKey(_startScreenKey).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
        reason: 'the start surface did not appear',
      );
      await tester.pumpAndSettle();

      final BuildContext startContext = tester.element(
        find.byKey(_startScreenKey),
      );
      final MediaQueryData media = MediaQuery.of(startContext);
      expect(
        media.textScaler.scale(10),
        closeTo(10 * _scaleFactor, 1e-6),
        reason: 'the audit must run at 200 % text',
      );
      _marker(
        'SCALE:${media.textScaler.scale(10).toStringAsFixed(2)}:'
        'size=${media.size.width.toStringAsFixed(1)}x'
        '${media.size.height.toStringAsFixed(1)}',
      );

      _reportText(_auditText(tester), 'start');
      _reportControls(_auditControls(tester), 'start');

      await tester.tap(find.byKey(_importActionKey));
      await _pumpUntil(
        tester,
        () => find.byKey(_editorScreenKey).evaluate().isNotEmpty,
        timeout: const Duration(minutes: 5),
        reason: 'the production import did not open the editor',
      );
      // The first analysis may still be running; settle only frames, never the
      // indeterminate progress state.
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      _reportText(_auditText(tester), 'editor');
      _reportControls(_auditControls(tester), 'editor');

      expect(tester.takeException(), isNull);
      semantics.dispose();
      _marker('AUDIT_COMPLETE');
    },
  );
}
