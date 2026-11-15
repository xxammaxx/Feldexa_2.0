// T011 fault taxonomy.
//
// Source: plan §Architecture Decisions 10 and research.md D-17. The listed
// failure modes are the ones recovery, atomicity, and destructive-cleanup
// guarantees must be tested against. Catalog codes mirror
// contracts/error-catalog.de.md; this file does not introduce new codes.

/// Injectable failure modes.
enum FaultKind {
  /// Filesystem quota exhausted (`ENOSPC`), mapped to `SAVE-001`.
  storageFull('SAVE-001', 'Storage quota exhausted (ENOSPC).'),

  /// Fewer bytes persisted than requested, mapped to `SAVE-003`.
  shortWrite('SAVE-003', 'Short write: fewer bytes persisted than requested.'),

  /// Durability barrier failed after the bytes were written.
  fsyncFailure('SAVE-003', 'Durability barrier (fsync) failed.'),

  /// Process or platform write was interrupted mid-commit.
  writeInterrupted('SAVE-003', 'Write interrupted before commit completed.'),

  /// Global Keystore provider is unavailable (not one aggregate's key).
  ///
  /// This is the temporary provider-outage context of `SAVE-008`, which is
  /// retryable.
  keystoreUnavailable('SAVE-008', 'Global Keystore provider is unavailable.'),

  /// A device-wide Keystore reset removed every stored aggregate key.
  ///
  /// This is the non-retryable context of `SAVE-008`; it is deliberately a
  /// separate kind because the same catalog code must not hide the missing
  /// recovery path.
  keystoreReset(
    'SAVE-008',
    'Device-wide Keystore reset; no aggregate key remains.',
  ),

  /// One aggregate's wrapped DEK failed authentication; integrity damage.
  corruptKeyMaterial(
    'SAVE-003',
    'Aggregate key material failed authentication or is corrupt.',
  ),

  /// Export pipeline failed before a verified artifact existed.
  exportFailure('EXP-002', 'Export failed before artifact verification.');

  const FaultKind(this.catalogCode, this.description);

  /// German error-catalog code this fault is expected to surface as.
  final String catalogCode;

  /// Short, content-free description.
  final String description;
}

/// Well-known fault-point names.
///
/// These are advisory: adapter implementations may use their own point names.
/// Stable names make cross-task failure scripts readable, and a later task can
/// replace a string without changing the injector.
abstract final class FaultPoints {
  static const String storeWrite = 'store.write';
  static const String storeStage = 'store.stage';
  static const String storeCommit = 'store.commit';
  static const String storeFsync = 'store.fsync';
  static const String storeRead = 'store.read';
  static const String keystoreUnwrap = 'keystore.unwrap';
  static const String exportValidate = 'export.validate';
  static const String exportWrite = 'export.write';
  static const String exportVerify = 'export.verify';
}
