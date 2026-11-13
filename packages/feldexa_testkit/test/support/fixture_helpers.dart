// Shared host-side helpers for the T011 fixture tests.
//
// These tests read the committed catalogue from the checkout. They are host-VM
// checks: the fixtures are SIMULATED inputs, but the test run itself produces
// no SIMULATED, EMULATOR, or DEVICE runtime evidence.

import 'dart:convert';
import 'dart:io';

import 'package:feldexa_testkit/io.dart';
import 'package:flutter_test/flutter_test.dart';

/// The checkout found by walking up from the package test working directory.
FixtureCheckout checkout() => FixtureCheckout.locate();

/// Raw bytes of the canonical catalogue.
String catalogSource() =>
    File('${checkout().canonicalDevDirectory}/catalog.json').readAsStringSync();

/// The committed catalogue as a mutable JSON object.
Map<String, Object?> catalogMap() {
  final Object? decoded = jsonDecode(catalogSource());
  if (decoded is! Map) {
    throw StateError('catalog.json is not an object');
  }
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in decoded.entries)
      entry.key.toString(): entry.value,
  };
}

/// A deep structural copy that tests may mutate.
Map<String, Object?> copyOfCatalog() {
  final Object? decoded = jsonDecode(jsonEncode(catalogMap()));
  if (decoded is! Map) {
    throw StateError('catalog copy is not an object');
  }
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in decoded.entries)
      entry.key.toString(): entry.value,
  };
}

/// The mutable fixture list inside [catalog].
List<Map<String, Object?>> fixturesIn(Map<String, Object?> catalog) {
  final Object? value = catalog['fixtures'];
  if (value is! List) {
    throw StateError('catalog.fixtures is not a list');
  }
  return value.cast<Map<String, Object?>>();
}

/// The mutable page list inside [fixture].
List<Map<String, Object?>> pagesIn(Map<String, Object?> fixture) {
  final Object? value = fixture['pages'];
  if (value is! List) {
    throw StateError('fixture.pages is not a list');
  }
  return value.cast<Map<String, Object?>>();
}

/// Matches a [FormatException] whose message contains [needle].
Matcher throwsFormatWith(String needle) => throwsA(
  isA<FormatException>().having(
    (FormatException error) => error.message.toString(),
    'message',
    contains(needle),
  ),
);
