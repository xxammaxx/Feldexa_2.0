// The shared `SIMULATED` evidence surface for FR-087 and constitution
// Principle II.
//
// Web development may substitute platform behavior, but the substitution must
// stay deterministic, visible, and honestly labeled: the exact English token
// `SIMULATED` is never translated, never hidden, and never presented as
// Android evidence. The plain-data [SimulatedEvidence] type is the single
// source of truth; the two widgets only render it.

import 'package:flutter/material.dart';

/// The contexts in which FR-087 requires the `SIMULATED` marker.
///
/// The set intentionally matches `contracts/error-catalog.de.md` §9. A new
/// surface must be added here and to [SimulatedEvidence.of] before a widget
/// can render it, so an unlabeled simulation path cannot be introduced by
/// accident.
enum SimulatedSurface {
  /// The persistent global banner on the Web development surface.
  globalBanner,

  /// The `[SIMULATED]` prefix for structured development logs.
  log,

  /// The footer of a simulated, non-production export artifact.
  exportFooter,

  /// The `evidenceClass: SIMULATED` field in test and report output.
  report,

  /// The notice on simulated, unencrypted development storage.
  storage,
}

/// The exact, untranslated evidence marker and its honest context.
///
/// This is production logic, not test scaffolding: UI, logs, reports, and
/// later app wiring consume the same immutable values. The class deliberately
/// does not model `EMULATOR` or `DEVICE`; those classes come from the platform
/// ports, and a simulated surface must never be promoted into them.
@immutable
final class SimulatedEvidence {
  const SimulatedEvidence._({
    required this.surface,
    required this.germanContext,
    required this.semanticsLabel,
  });

  /// The mandatory English token. It is never translated (FR-087).
  static const String token = 'SIMULATED';

  /// The exact log prefix required by `contracts/error-catalog.de.md` §9.
  static const String logPrefix = '[SIMULATED]';

  /// The exact report field required by `contracts/error-catalog.de.md` §9.
  static const String reportField = 'evidenceClass: SIMULATED';

  /// The evidence class name used in reports and artifacts.
  static const String evidenceClass = 'SIMULATED';

  /// The German context line for the global Web banner.
  static const String bannerContext =
      'Entwicklungsansicht: Plattformfunktionen sind simuliert. '
      'Ergebnisse gelten nicht als Android-Nachweis.';

  /// The German context line for a simulated export artifact.
  static const String exportFooterContext =
      'Simuliertes PDF – kein Produktionsartefakt.';

  /// The German context line for simulated storage.
  static const String storageContext =
      'Simulierter Speicher – keine echte Verschlüsselung.';

  /// The exact test-asserted accessibility label for the global banner.
  static const String bannerSemanticsLabel =
      'SIMULATED – Entwicklungsansicht mit simulierten Plattformfunktionen. '
      'Keine Android-Prüfung.';

  /// The global Web banner descriptor.
  static const SimulatedEvidence banner = SimulatedEvidence._(
    surface: SimulatedSurface.globalBanner,
    germanContext: bannerContext,
    semanticsLabel: bannerSemanticsLabel,
  );

  /// The structured-log prefix descriptor.
  static const SimulatedEvidence log = SimulatedEvidence._(
    surface: SimulatedSurface.log,
    germanContext: null,
    semanticsLabel: 'SIMULATED – Entwicklungsprotokoll. Kein Android-Nachweis.',
  );

  /// The simulated-export footer descriptor.
  static const SimulatedEvidence exportFooter = SimulatedEvidence._(
    surface: SimulatedSurface.exportFooter,
    germanContext: exportFooterContext,
    semanticsLabel:
        'SIMULATED – Simuliertes PDF – kein Produktionsartefakt. '
        'Kein Android-Nachweis.',
  );

  /// The test/report field descriptor.
  static const SimulatedEvidence report = SimulatedEvidence._(
    surface: SimulatedSurface.report,
    germanContext: null,
    semanticsLabel: 'SIMULATED – Entwicklungsbericht. Kein Android-Nachweis.',
  );

  /// The simulated-storage descriptor.
  static const SimulatedEvidence storage = SimulatedEvidence._(
    surface: SimulatedSurface.storage,
    germanContext: storageContext,
    semanticsLabel:
        'SIMULATED – Simulierter Speicher – keine echte Verschlüsselung. '
        'Kein Android-Nachweis.',
  );

  /// Returns the descriptor for a catalogued [surface].
  factory SimulatedEvidence.of(SimulatedSurface surface) => switch (surface) {
    SimulatedSurface.globalBanner => SimulatedEvidence.banner,
    SimulatedSurface.log => SimulatedEvidence.log,
    SimulatedSurface.exportFooter => SimulatedEvidence.exportFooter,
    SimulatedSurface.report => SimulatedEvidence.report,
    SimulatedSurface.storage => SimulatedEvidence.storage,
  };

  /// The surface this descriptor labels.
  final SimulatedSurface surface;

  /// The German context line, or `null` for machine-only surfaces (log/report).
  final String? germanContext;

  /// The complete screen-reader label for the surface.
  ///
  /// It always carries the exact token and an explicit statement that the
  /// surface is not Android verification.
  final String semanticsLabel;

  /// The text the surface must display: the token, its log prefix, or the
  /// exact report field. Never a translated token.
  String get marker => switch (surface) {
    SimulatedSurface.globalBanner => token,
    SimulatedSurface.log => logPrefix,
    SimulatedSurface.exportFooter => token,
    SimulatedSurface.report => reportField,
    SimulatedSurface.storage => token,
  };

  /// Whether this evidence may be presented as Android runtime verification.
  ///
  /// Always `false`. Simulated browser behavior is not Android evidence
  /// (constitution Principles II, III, and VIII).
  bool get isAndroidVerification => false;

  /// Whether this evidence may be presented as a production artifact.
  ///
  /// Always `false`; simulated output remains a development artifact.
  bool get isProductionArtifact => false;

  /// The report fields this evidence contributes.
  ///
  /// Only the evidence class is emitted; there is no path that upgrades a
  /// simulated result into `EMULATOR` or `DEVICE`.
  Map<String, Object?> toReportFields() => const <String, Object?>{
    'evidenceClass': evidenceClass,
  };
}

/// The persistent global `SIMULATED` banner for the Web development surface.
///
/// The banner is not dismissible and contains no close action: hiding the
/// marker would violate FR-087. The exact token, the German context line, and
/// the complete accessibility label all come from [SimulatedEvidence.banner].
///
/// Layout is text-scalable and wraps at narrow widths. The fixed dark/amber
/// palette keeps the marker at high contrast independently of the app theme.
class SimulatedBanner extends StatelessWidget {
  /// Creates the global SIMULATED banner.
  const SimulatedBanner({super.key});

  /// The descriptor rendered by this banner.
  static const SimulatedEvidence evidence = SimulatedEvidence.banner;

  /// High-contrast background shared with [SimulatedEvidenceLabel].
  static const Color backgroundColor = Color(0xFF202124);

  /// High-contrast color for the untranslated token.
  static const Color tokenColor = Color(0xFFFFD54F);

  /// High-contrast color for German context text.
  static const Color contextColor = Color(0xFFF1F3F4);

  /// Border color for the compact evidence label.
  static const Color borderColor = Color(0xFFFFD54F);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: evidence.semanticsLabel,
      child: ExcludeSemantics(
        child: Material(
          color: backgroundColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.science_outlined, color: tokenColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(evidence.marker, style: _tokenStyle(context)),
                      const SizedBox(height: 4),
                      Text(
                        evidence.germanContext!,
                        style: _contextStyle(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact `SIMULATED` evidence label for logs, reports, simulated exports,
/// and simulated storage notices.
///
/// It renders exactly the marker from [SimulatedEvidence.marker] and, where
/// the catalog defines one, the German context line. The label is intended for
/// constrained containers; its [Wrap] keeps the token and context visible at
/// 200 % text scale.
class SimulatedEvidenceLabel extends StatelessWidget {
  /// Creates a compact evidence label for a non-banner [surface].
  const SimulatedEvidenceLabel({super.key, required this.surface});

  /// The catalogued surface to label.
  final SimulatedSurface surface;

  @override
  Widget build(BuildContext context) {
    final SimulatedEvidence evidence = SimulatedEvidence.of(surface);
    return Semantics(
      container: true,
      label: evidence.semanticsLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: SimulatedBanner.backgroundColor,
            border: Border.all(color: SimulatedBanner.borderColor, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                Text(evidence.marker, style: _tokenStyle(context)),
                if (evidence.germanContext != null)
                  Text(evidence.germanContext!, style: _contextStyle(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _tokenStyle(BuildContext context) {
  final TextStyle base =
      Theme.of(context).textTheme.titleSmall ?? const TextStyle();
  return base.copyWith(
    color: SimulatedBanner.tokenColor,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );
}

TextStyle _contextStyle(BuildContext context) {
  final TextStyle base =
      Theme.of(context).textTheme.bodySmall ?? const TextStyle();
  return base.copyWith(color: SimulatedBanner.contextColor);
}
