// T148 Android import and source read-back composition; issue #217 Phase B1
// adds the editor runtime.
//
// Owner: `apps/feldexa_app/lib/features/start/import_runtime_android.dart`
// (T148, Phase B1). Selected only by the conditional import in
// `import_runtime.dart` on `dart.library.io` targets; the Web build never
// resolves this file or the `feldexa_adapters_android` package.
//
// `AndroidImportClient` is the real `DocumentImportPort`; no simulated adapter
// is constructed here. The store client is the runtime read-back path for the
// viewer: `AndroidStoreClient.loadDocument` verifies the committed metadata and
// revision against the head and invokes the `store.readSource` channel method
// (`contracts/platform-channel.md` §4) to return the decrypted protected bytes.
// The viewer never receives a path, URI, or display name.
//
// Phase B1 shares this composition's one operation client and store with each
// editor session, so the app does not open a second result stream. The editor
// runtime does not dispose the shared clients; it disposes only its raster/OCR
// state.

import 'package:feldexa_adapters_android/feldexa_adapters_android.dart';
import 'package:feldexa_ports/feldexa_ports.dart';

import '../editor/editor_runtime_android.dart';
import 'import_runtime.dart';

/// Builds the real Android import composition.
ImportRuntime createImportRuntime() {
  // One operation client owns the result stream for the import, store, and
  // editor clients of this composition.
  final AndroidOperationClient operations = AndroidOperationClient();
  final AndroidStoreClient store = AndroidStoreClient(operations: operations);
  return ImportRuntime(
    importPort: AndroidImportClient(operations: operations),
    readSourceBytes: (String documentId) async {
      final LoadedDocument loaded = await store.loadDocument(documentId);
      return loaded.sourceBytes;
    },
    editorRuntimeFactory: () => createAndroidEditorRuntime(
      operations: operations,
      store: store,
      ownsOperations: false,
    ),
  );
}
