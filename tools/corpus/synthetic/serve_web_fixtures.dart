// Minimal static server for the T009 Web fixture runtime check.
//
// The Flutter Web dev server and `flutter build web` serve `web/fixtures/` at
// `/fixtures/...`. This server reproduces that URL layout over `build/web`
// (or `web/`) so the browser test can fetch the real files with CORS enabled.
//
// Usage:
//   dart run tools/corpus/synthetic/serve_web_fixtures.dart \
//     --root apps/feldexa_app/build/web --port 8765
//
// It is a host test tool: loopback only, no caching, no directory listing, no
// writes. It produces no product evidence by itself.

import 'dart:io';

Future<void> main(List<String> arguments) async {
  final _Options options = _parseArguments(arguments);
  final Directory root = Directory(options.root).absolute;
  if (!root.existsSync()) {
    stderr.writeln('error: fixture root does not exist: ${root.path}');
    exitCode = 2;
    return;
  }

  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    options.port,
  );
  stdout.writeln(
    'T009 fixture server: http://127.0.0.1:${server.port}/fixtures/ '
    '(root ${root.path})',
  );

  await for (final HttpRequest request in server) {
    await _handle(request, root);
  }
}

Future<void> _handle(HttpRequest request, Directory root) async {
  final HttpResponse response = request.response;
  stdout.writeln('${request.method} ${request.uri.path}');
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  response.headers.set('Access-Control-Allow-Headers', '*');
  response.headers.set('Access-Control-Allow-Private-Network', 'true');
  response.headers.set('Cache-Control', 'no-store');

  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }
  if (request.method != 'GET' && request.method != 'HEAD') {
    response.statusCode = HttpStatus.methodNotAllowed;
    await response.close();
    return;
  }

  final String requestedPath = Uri.decodeComponent(request.uri.path);
  if (requestedPath.contains('..')) {
    response.statusCode = HttpStatus.badRequest;
    await response.close();
    return;
  }
  final File file = File('${root.path}$requestedPath');
  final String normalizedRoot = '${root.path}${Platform.pathSeparator}';
  if (!file.absolute.path.startsWith(normalizedRoot)) {
    response.statusCode = HttpStatus.forbidden;
    await response.close();
    return;
  }
  if (!file.existsSync() || file.statSync().type != FileSystemEntityType.file) {
    response.statusCode = HttpStatus.notFound;
    await response.close();
    return;
  }

  final String extension = file.path.split('.').last;
  response.headers.contentType = switch (extension) {
    'json' => ContentType('application', 'json', charset: 'utf-8'),
    'pdf' => ContentType('application', 'pdf'),
    'md' => ContentType('text', 'markdown', charset: 'utf-8'),
    _ => ContentType.binary,
  };
  response.contentLength = file.lengthSync();
  if (request.method == 'HEAD') {
    await response.close();
    return;
  }
  await response.addStream(file.openRead());
  await response.close();
}

class _Options {
  const _Options({required this.root, required this.port});

  final String root;
  final int port;
}

_Options _parseArguments(List<String> arguments) {
  String root = 'apps/feldexa_app/build/web';
  int port = 8765;
  for (int index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--root':
        index++;
        if (index >= arguments.length) {
          _usage('--root requires a directory');
        }
        root = arguments[index];
      case '--port':
        index++;
        if (index >= arguments.length) {
          _usage('--port requires a number');
        }
        final int? parsed = int.tryParse(arguments[index]);
        if (parsed == null || parsed <= 0 || parsed > 65535) {
          _usage('--port must be 1..65535');
        }
        port = parsed;
      case '--help' || '-h':
        stdout.write(_usageText);
        exit(0);
      default:
        _usage('unknown argument "${arguments[index]}"');
    }
  }
  return _Options(root: root, port: port);
}

Never _usage(String message) {
  stderr.writeln('error: $message');
  stderr.write(_usageText);
  exit(2);
}

const String _usageText = '''
T009 Web fixture server

Usage:
  dart run tools/corpus/synthetic/serve_web_fixtures.dart [options]

Options:
  --root DIR   Directory served as the site root (default:
               apps/feldexa_app/build/web; use apps/feldexa_app/web for the
               source tree).
  --port N     Loopback port (default: 8765).
  --help, -h   Show this help.

Serves the root at http://127.0.0.1:<port>/ with CORS enabled so the Chrome
runtime test can fetch /fixtures/... exactly as the Flutter Web dev server does.
''';
