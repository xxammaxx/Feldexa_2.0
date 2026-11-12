@TestOn('vm')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// T006 asset-bundling contract: the Flutter asset bundle contains the exact
/// pinned Noto Sans Regular/Bold bytes and the SIL OFL 1.1 text.
///
/// This is a host-VM asset check. It does not lay out or render text and
/// produces no `SIMULATED`, `EMULATOR`, or `DEVICE` evidence. T030 owns metric
/// parity with `metrics.json`; T007 generates that file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fonts = <String, int>{
    'assets/fonts/NotoSans-Regular.ttf': 790500,
    'assets/fonts/NotoSans-Bold.ttf': 802504,
  };

  for (final entry in fonts.entries) {
    test('asset bundle contains ${entry.key}', () async {
      final data = await rootBundle.load(entry.key);

      expect(data.lengthInBytes, entry.value);
      // Static TrueType sfnt version.
      expect(data.getUint32(0), 0x00010000);

      final tableCount = data.getUint16(4);
      expect(tableCount, greaterThan(0));
      final tags = <String>{};
      for (var index = 0; index < tableCount; index++) {
        final base = 12 + index * 16;
        tags.add(
          String.fromCharCodes(
            List<int>.generate(4, (offset) => data.getUint8(base + offset)),
          ),
        );
      }

      expect(tags, containsAll(<String>['cmap', 'glyf', 'head', 'loca']));
      expect(tags, isNot(contains('fvar')), reason: 'T006 pins static TTFs');
      expect(tags, isNot(contains('CFF ')), reason: 'TrueType outlines only');
    });
  }

  test('asset bundle contains the SIL OFL 1.1 text', () async {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');

    expect(license, contains('Copyright 2022 The Noto Project Authors'));
    expect(license, contains('SIL Open Font License, Version 1.1'));
    expect(license, contains('PERMISSION & CONDITIONS'));
    expect(license, contains('TERMINATION'));
    expect(license, contains('DISCLAIMER'));
  });
}
