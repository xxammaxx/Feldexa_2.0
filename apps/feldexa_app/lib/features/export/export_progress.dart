// Issue #334 export progress and cancellation seam (§10 point 3).
//
// Owner: `apps/feldexa_app/lib/features/export/export_progress.dart`.
//
// Normative sources:
//   * `contracts/editor-interactions.md` §10 point 3 — „Export starten“ shows
//     progress phases with a cancel action;
//   * `contracts/platform-channel.md` §6 and §8.1 — the `export.progress`
//     phases `importing|drawing|verifying|finalizing`, best-effort and free of
//     any content;
//   * `contracts/platform-channel.md` §9 — `cancel.operation` is synchronous,
//     is impossible before the start reply, and publishes the terminal
//     `PLT-004` of a cancelled operation.
//
// This seam adds no port and no channel. It carries what the editor needs to
// render §10 point 3 — a phase, a fraction, and the cancellation answer — and
// the Android composition adapts the existing `export.progress` events and the
// existing `cancel.operation` call of the one platform channel onto it. It
// never carries a value, label, path, URI, or artifact id, so nothing
// content-bearing can reach a progress surface.

/// The four render phases of `contracts/platform-channel.md` §6.
enum ExportPhase {
  /// The stored source PDF is read and checked against the plan hash.
  importing('importing'),

  /// Every page is copied and receives its overlay operations.
  drawing('drawing'),

  /// The written artifact is verified before anything is published.
  verifying('verifying'),

  /// The verified artifact is renamed into place and published.
  finalizing('finalizing');

  const ExportPhase(this.wireName);

  /// The stable contract token of §6; a machine identifier, never shown.
  final String wireName;
}

/// One content-free progress step of the running export (§6, §8.1).
final class ExportProgress {
  const ExportProgress({required this.phase, required this.fraction});

  /// The phase the platform reported.
  final ExportPhase phase;

  /// Best-effort completion in `0.0 … 1.0`; never authoritative (§8.1).
  final double fraction;
}

/// Progress and cancellation of the export of one editor session.
abstract interface class ExportOperationControl {
  /// Best-effort steps of the running export.
  ///
  /// Duplicate, missing, and late steps are legal (§8.1): a caller must render
  /// a step and must never derive a result from it. The stream ends or stays
  /// silent when the composition cannot report progress at all.
  Stream<ExportProgress> get progress;

  /// Requests cancellation of the running export and returns the platform's
  /// answer.
  ///
  /// `false` means "nothing was cancelled": no operation is running, either
  /// before the start reply or after the terminal result (§9). A claimed
  /// cancellation is not inferred from `true` alone — the terminal `PLT-004`
  /// result reports it — and a throwing call means the same as `false`; the
  /// export then simply keeps running.
  Future<bool> cancel();
}

/// The control of a composition that has no cancellable export operation.
///
/// It reports no progress and cancels nothing instead of pretending either. An
/// unavailable runtime and a host-VM test fake resolve it, so the editor can
/// render §10 point 3 without claiming a platform capability that is absent.
final class UnavailableExportOperationControl
    implements ExportOperationControl {
  const UnavailableExportOperationControl();

  @override
  Stream<ExportProgress> get progress => const Stream<ExportProgress>.empty();

  @override
  Future<bool> cancel() async => false;
}
