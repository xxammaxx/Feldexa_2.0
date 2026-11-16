// T027 Android thin clients.
//
// The adapter package is the only Dart code that talks to the Feldexa
// MethodChannel/result channel and the bundled PDFium renderer. Application
// code consumes these through `feldexa_ports`; it never imports this barrel
// outside the Android composition root.

export 'src/android_channel.dart';
export 'src/android_delivery_client.dart';
export 'src/android_export_client.dart';
export 'src/android_import_client.dart';
export 'src/android_ocr_client.dart';
export 'src/android_operation_client.dart';
export 'src/android_raster_client.dart';
export 'src/android_store_client.dart';
export 'src/android_system_clients.dart';
