// T011 fixture-source tests.
//
// Host-VM tests of path safety, defensive copying, and missing-file errors.
// No runtime evidence is produced.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:feldexa_testkit/feldexa_testkit.dart';
import 'package:feldexa_testkit/io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateFixturePath', () {
    test('accepts portable relative paths', () {
      expect(validateFixturePath('catalog.json'), 'catalog.json');
      expect(validateFixturePath('sub/dir/file.pdf'), 'sub/dir/file.pdf');
    });

    test('rejects absolute, traversal, and Windows-separated paths', () {
      for (final String path in <String>[
        '',
        '/etc/passwd',
        '//server/share',
        r'C:\outside',
        'C:/outside',
        'C:outside',
        r'\\server\share',
        r'..\..\outside',
        r'sub\dir\file.pdf',
        '../catalog.json',
        'dir/../catalog.json',
        'dir//catalog.json',
        './catalog.json',
        'dir/',
        'dir./catalog.json',
        'dir /catalog.json',
        '.. /catalog.json',
        '.../catalog.json',
        '.',
        '..',
        'catalog.json\u0000',
        'catalog\u0001.json',
      ]) {
        expect(
          () => validateFixturePath(path),
          throwsArgumentError,
          reason: path,
        );
      }
    });
  });

  group('validatePortableRelativePath', () {
    test('returns accepted paths unchanged', () {
      expect(
        validatePortableRelativePath('apps/fixtures', label: 'dir'),
        'apps/fixtures',
      );
    });

    test('rejects backslash traversal with a format error', () {
      expect(
        () => validatePortableRelativePath(r'..\..\outside', label: 'dir'),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message.toString(),
            'message',
            contains('backslash'),
          ),
        ),
      );
    });

    test('rejects empty, absolute, dot, and trailing-segment paths', () {
      for (final String path in <String>[
        '',
        '/absolute',
        '..',
        '.',
        'a/../b',
        'a/./b',
        'a//b',
        'a/',
        'a./b',
        'a /b',
        '.. /b',
        '.../b',
      ]) {
        expect(
          () => validatePortableRelativePath(path, label: 'dir'),
          throwsFormatException,
          reason: path,
        );
      }
    });
  });

  group('validateWebBasePath', () {
    test('accepts a site-absolute fixture base', () {
      expect(validateWebBasePath('/fixtures', label: 'base'), '/fixtures');
      expect(
        validateWebBasePath('/fixtures/v1', label: 'base'),
        '/fixtures/v1',
      );
    });

    test(
      'rejects protocol-relative, traversing, query, and fragment bases',
      () {
        for (final String value in <String>[
          'fixtures',
          'https://evil.example/fixtures',
          '//evil.example/fixtures',
          '/',
          '/fixtures/../outside',
          r'/fixtures\..\outside',
          r'/..\..\outside',
          '/fixtures?x=1',
          '/fixtures#fragment',
        ]) {
          expect(
            () => validateWebBasePath(value, label: 'base'),
            throwsFormatException,
            reason: value,
          );
        }
      },
    );
  });

  group('InMemoryFixtureSource', () {
    test('rejects unsafe source keys', () {
      expect(
        () => InMemoryFixtureSource(<String, List<int>>{
          r'..\..\outside': <int>[1],
        }),
        throwsArgumentError,
      );
    });
    test('reads copies and refuses missing files', () async {
      final InMemoryFixtureSource source = InMemoryFixtureSource.fromText(
        <String, String>{'a.txt': 'hello'},
      );
      expect(source.contains('a.txt'), isTrue);
      expect(source.contains('b.txt'), isFalse);
      expect(source.paths, <String>['a.txt']);
      expect(source.description, 'in-memory (1 files)');

      final Uint8List first = await source.read('a.txt');
      expect(utf8.decode(first), 'hello');
      first[0] = 0xff;
      final Uint8List second = await source.read('a.txt');
      expect(utf8.decode(second), 'hello');

      await expectLater(
        source.read('missing.txt'),
        throwsA(isA<FixtureSourceException>()),
      );
    });

    test('copies caller bytes at construction', () async {
      final List<int> bytes = <int>[1, 2, 3];
      final InMemoryFixtureSource source = InMemoryFixtureSource(
        <String, List<int>>{'a.bin': bytes},
      );
      bytes[0] = 9;
      expect(await source.read('a.bin'), <int>[1, 2, 3]);
    });
  });

  group('FileFixtureSource', () {
    test('reports a missing file with its delivery-relative path', () async {
      final FixtureCheckout checkout = FixtureCheckout.locate();
      final FileFixtureSource source = FileFixtureSource(
        checkout.canonicalDevDirectory,
      );
      await expectLater(
        source.read('does-not-exist.pdf'),
        throwsA(
          isA<FixtureSourceException>().having(
            (FixtureSourceException error) => error.path,
            'path',
            'does-not-exist.pdf',
          ),
        ),
      );
    });

    test('rejects Windows traversal before touching the filesystem', () async {
      final FixtureCheckout checkout = FixtureCheckout.locate();
      final FileFixtureSource source = FileFixtureSource(
        checkout.canonicalDevDirectory,
      );
      await expectLater(source.read(r'..\..\outside'), throwsArgumentError);
      await expectLater(source.read(r'C:\outside'), throwsArgumentError);
    });

    test('locates the workspace root from a nested directory', () {
      final FixtureCheckout root = FixtureCheckout.locate();
      final FixtureCheckout nested = FixtureCheckout.locate(
        fromDirectory: '${root.rootDirectory}/packages/feldexa_testkit',
      );
      expect(nested.rootDirectory, root.rootDirectory);
      expect(
        File('${nested.rootDirectory}/pubspec.yaml').readAsStringSync(),
        contains('name: feldexa_workspace'),
      );
    });
  });
}
