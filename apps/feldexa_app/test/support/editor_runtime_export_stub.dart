// Shared fail-closed export/delivery members for `EditorRuntime` test fakes.
//
// Owner: `apps/feldexa_app/test/support/editor_runtime_export_stub.dart`.
//
// The editor fakes of the Phase A/B widget tests exist to exercise loading,
// analysis, review, geometry, and signature flows. They must satisfy
// `EditorRuntime` without pretending that a platform export, a delivery
// hand-off, or a screenshot protection exists on the host VM: the ports throw
// `UnsupportedOperationException` and `setSensitiveRoute` reports "not
// protected" (`false`) exactly as an unattached Android window would.
//
// Tests that exercise the export flow itself use their own recording fakes
// instead of this stub.

import 'package:feldexa_app/features/editor/editor_runtime.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

/// Fail-closed `export`, `delivery`, and `setSensitiveRoute` members.
mixin FakeEditorRuntimeExportStub implements EditorRuntime {
  @override
  PdfExportPort get export => throw UnsupportedOperationException();

  @override
  DeliveryPort get delivery => throw UnsupportedOperationException();

  /// Reports "not protected"; a host test has no window to apply the flag to
  /// and must never read as a protected route.
  @override
  Future<bool> setSensitiveRoute(SensitiveRoute route) async => false;
}
