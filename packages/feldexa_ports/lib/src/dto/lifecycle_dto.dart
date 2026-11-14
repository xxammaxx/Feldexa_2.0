// T013 `LifecyclePort` signal vocabulary.
//
// Owner: `packages/feldexa_ports/lib/src/dto/lifecycle_dto.dart` (T013).
// Normative source: `contracts/ports.md` §2.7.
//
// `paused` and `inactive` trigger the autosave flush attempt described by
// FR-045/FR-046; the last verified commit remains the only durability claim.

/// Application lifecycle signals delivered by `LifecyclePort`
/// (`contracts/ports.md` §2.7).
enum AppLifecycleSignal {
  /// The app is visible and interactive.
  resumed,

  /// The app is visible but not receiving input.
  inactive,

  /// The app is no longer visible.
  paused,

  /// The app is being detached from the platform view hierarchy.
  detached,
}
