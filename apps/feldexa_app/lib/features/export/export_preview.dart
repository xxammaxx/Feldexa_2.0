// Issue #334 export preview route (T106/T107 UI).
//
// Owner: `apps/feldexa_app/lib/features/export/export_preview.dart`.
//
// Normative sources:
//   * `contracts/editor-interactions.md` §10 points 4–6 — the preview route
//     with „Speichern“, „Teilen“, „Drucken“, and „Schließen“, and the
//     ephemeral artifact being deleted after the session;
//   * `contracts/error-catalog.de.md` §4 — the success sentence, the preview
//     footer, and the delivery vocabulary; §10 — the developer-only codes;
//   * `contracts/platform-channel.md` §7 (delivery) and §11 point 7
//     (`FLAG_SECURE` on the export route);
//   * `contracts/storage-format.md` §4 step 4 — preview artifacts are never
//     durable and are swept at session end;
//   * FR-070, FR-071, FR-072, and FR-073.
//
// The preview shows only what the verified artifact record carries: its page
// count and its byte size. It never holds, requests, or renders the artifact
// bytes, a path, or a URI, and it prints nothing. Delivery is a single port
// call per action; a user cancellation is not an error (`DEL-001`).
//
// The artifact is deleted when the route is left and when the platform detaches
// the view. Deletion is best-effort but idempotent: a failed delete never
// reports success, the native facade deletes session artifacts on detach, and
// the startup sweep removes anything that outlived the process.

import 'dart:async';

import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_app/l10n/app_localizations.dart';
import 'package:feldexa_export/feldexa_export.dart';
import 'package:feldexa_ports/feldexa_ports.dart';
import 'package:flutter/material.dart';

/// Stable key of the preview route.
const ValueKey<String> exportPreviewRouteKey = ValueKey<String>(
  'export-preview-route',
);

/// Stable key of the content-free marker a failed delivery leaves behind.
///
/// A failed save/share/print has no German catalog sentence: `DEL-001` covers
/// only cancellation and the native failures are the developer-only `PLT-001`.
/// The preview therefore invents no wording; it re-enables the action and
/// records this state for tests and diagnostics.
const String exportPreviewDeliveryFailedKey = 'export-preview-delivery-failed';

/// The export preview route for one verified artifact.
class ExportPreviewScreen extends StatefulWidget {
  /// Creates the preview for [artifact].
  ///
  /// [runtime] supplies the delivery port, the artifact deletion, and the
  /// `platform.sensitiveRoute` capability of the same session.
  const ExportPreviewScreen({
    required this.runtime,
    required this.artifact,
    super.key,
  });

  /// The editor session runtime.
  final EditorRuntime runtime;

  /// The verified artifact produced by the export.
  final ExportArtifact artifact;

  @override
  State<ExportPreviewScreen> createState() => _ExportPreviewScreenState();
}

class _ExportPreviewScreenState extends State<ExportPreviewScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _deleted = false;
  bool _deliveryFailed = false;
  String? _locationHint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_applySensitiveRoute(SensitiveRoute.export));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // The view is going away; the artifact must not outlive the session.
      unawaited(_deleteArtifact());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_leaveRoute());
    super.dispose();
  }

  /// Deletes the artifact, then returns the route protection to the editor.
  Future<void> _leaveRoute() async {
    await _deleteArtifact();
    await _applySensitiveRoute(SensitiveRoute.editor);
  }

  /// Applies [route]; a failure is recorded as "not protected", never assumed.
  Future<void> _applySensitiveRoute(SensitiveRoute route) async {
    try {
      await widget.runtime.setSensitiveRoute(route);
    } catch (_) {
      // Fail-safe: the preview stays usable and claims no protection.
    }
  }

  /// Deletes the session artifact once.
  Future<void> _deleteArtifact() async {
    if (_deleted) {
      return;
    }
    _deleted = true;
    try {
      await widget.runtime.export.deleteArtifact(widget.artifact.id);
    } catch (_) {
      // The native facade and the startup sweep own the remaining cleanup; a
      // failed delete is never reported as a successful one.
    }
  }

  Future<void> _deliver(DeliveryAction action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _deliveryFailed = false;
    });
    DeliveryOutcome? outcome;
    try {
      outcome = await widget.runtime.delivery.deliver(
        action: action,
        artifactId: widget.artifact.id,
      );
    } catch (_) {
      // Delivery failures are the developer-only `PLT-001` on the channel; the
      // catalog has no German sentence for them. No wording is invented.
      outcome = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      // `completed: false` is a user cancellation and not an error (§7,
      // `DEL-001`); only a thrown failure is reported here.
      _deliveryFailed = outcome == null;
      _locationHint = outcome?.userVisibleLocationHint;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    // A verified artifact always carries both values; a null one is shown as
    // absent instead of as a zero that the record does not claim.
    final int? pageCount = widget.artifact.pageCount;
    final int? byteSize = widget.artifact.byteSize;
    return Scaffold(
      key: exportPreviewRouteKey,
      appBar: AppBar(title: Text(l10n.previewFooter)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_deliveryFailed)
              SizedBox.shrink(
                key: const ValueKey<String>(exportPreviewDeliveryFailedKey),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l10n.exportSuccess, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    if (pageCount != null)
                      Text(
                        l10n.exportPreviewPageCount(pageCount),
                        style: theme.textTheme.bodyLarge,
                      ),
                    if (pageCount != null && byteSize != null)
                      const SizedBox(height: 4),
                    if (byteSize != null)
                      Text(
                        l10n.exportPreviewFileSize(
                          formatExportByteSize(byteSize),
                        ),
                        style: theme.textTheme.bodyLarge,
                      ),
                    if (_locationHint != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(_locationHint!, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    key: const ValueKey<String>('export-preview-save'),
                    onPressed: _busy
                        ? null
                        : () {
                            unawaited(_deliver(DeliveryAction.save));
                          },
                    icon: const Icon(Icons.save_alt),
                    label: Text(l10n.exportPreviewSaveAction),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('export-preview-share'),
                    onPressed: _busy
                        ? null
                        : () {
                            unawaited(_deliver(DeliveryAction.share));
                          },
                    icon: const Icon(Icons.share),
                    label: Text(l10n.exportPreviewShareAction),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('export-preview-print'),
                    onPressed: _busy
                        ? null
                        : () {
                            unawaited(_deliver(DeliveryAction.print));
                          },
                    icon: const Icon(Icons.print),
                    label: Text(l10n.exportPreviewPrintAction),
                  ),
                  TextButton(
                    key: const ValueKey<String>('export-preview-close'),
                    onPressed: () {
                      unawaited(Navigator.of(context).maybePop());
                    },
                    child: Text(l10n.exportCloseAction),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats [bytes] as a German size label without a locale-dependent number
/// format: bytes, kilobytes, or megabytes with one decimal and a comma.
String formatExportByteSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${_germanDecimal(bytes / 1024)} kB';
  }
  return '${_germanDecimal(bytes / (1024 * 1024))} MB';
}

String _germanDecimal(double value) {
  return value.toStringAsFixed(1).replaceAll('.', ',');
}
