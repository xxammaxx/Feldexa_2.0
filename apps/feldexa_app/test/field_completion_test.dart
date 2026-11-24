// T085 per-field completion state classifier host tests.
//
// Evidence class: NONE. These are host-VM unit tests over synthetic values.
// They create no document, open no editor, call no store or network, and make
// no Android, device, screen-reader, or visual claim.
//
// They prove the pinned T085 behaviour:
//   * empty and whitespace-only text and multiline values are optional-empty;
//   * non-empty text and multiline values are complete;
//   * both checkbox states are complete, because unchecked is explicit;
//   * number, date, and signature values are complete;
//   * a null value with ok validation is optional-empty;
//   * a blocking error wins over every value, including incompatible content;
//   * incompatible content wins over a warning and is blocking;
//   * a warning wins over an empty optional value;
//   * the extension predicates map exactly onto the five states;
//   * the production source imports only `feldexa_core`.

@TestOn('vm')
library;

import 'dart:io';

import 'package:feldexa_app/features/editor/field_completion.dart';
import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';

import 'support/package_root.dart';

/// Fixed UTC commit timestamp; never the wall clock.
final DateTime _editedAt = DateTime.utc(2026, 11, 20);

/// A valid lowercase UUIDv4 for the synthetic signature asset.
const String _signatureAssetId = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

core.TextValue _text(String text) =>
    core.TextValue(text: text, lastEditedAt: _editedAt);

core.MultilineValue _multiline(String text) =>
    core.MultilineValue(text: text, lastEditedAt: _editedAt);

core.CheckboxValue _checkbox({required bool checked}) =>
    core.CheckboxValue(checked: checked, lastEditedAt: _editedAt);

core.NumberValue _number() => core.NumberValue(
  canonical: '1234.5',
  rawGerman: '1.234,5',
  lastEditedAt: _editedAt,
);

core.DateValue _date() =>
    core.DateValue(canonical: '2026-11-20', lastEditedAt: _editedAt);

core.SignatureValue _signature() => core.SignatureValue(
  signatureAssetId: _signatureAssetId,
  lastEditedAt: _editedAt,
);

core.IncompatibleValue _incompatible({String preservedText = 'kept text'}) =>
    core.IncompatibleValue(
      preservedText: preservedText,
      reasonCode: 'type_changed',
      lastEditedAt: _editedAt,
    );

core.FieldValidation _error() => core.FieldValidation.error('NUM-001');

core.FieldValidation _warning() =>
    core.FieldValidation.warning(core.WarningCode.overflow, 'fld001');

FieldCompletionState _classify(
  core.FieldValue? value, {
  core.FieldValidation validation = core.FieldValidation.ok,
}) {
  return fieldCompletionState(validation: validation, value: value);
}

void main() {
  group('text and multiline values', () {
    test('empty text is optional-empty', () {
      expect(_classify(_text('')), FieldCompletionState.optionalEmpty);
    });

    test('whitespace-only text is optional-empty', () {
      expect(_classify(_text('   ')), FieldCompletionState.optionalEmpty);
    });

    test('non-empty text is complete', () {
      expect(_classify(_text('invoice 42')), FieldCompletionState.complete);
    });

    test('empty multiline is optional-empty', () {
      expect(_classify(_multiline('')), FieldCompletionState.optionalEmpty);
    });

    test('whitespace and newline-only multiline is optional-empty', () {
      expect(
        _classify(_multiline(' \n  ')),
        FieldCompletionState.optionalEmpty,
      );
      expect(
        _classify(_multiline('\n\n  ')),
        FieldCompletionState.optionalEmpty,
      );
    });

    test('non-empty multiline is complete', () {
      expect(
        _classify(_multiline('line one\nline two')),
        FieldCompletionState.complete,
      );
    });
  });

  group('non-text values', () {
    test('an unchecked checkbox is complete', () {
      expect(
        _classify(_checkbox(checked: false)),
        FieldCompletionState.complete,
      );
    });

    test('a checked checkbox is complete', () {
      expect(
        _classify(_checkbox(checked: true)),
        FieldCompletionState.complete,
      );
    });

    test('a number value is complete', () {
      expect(_classify(_number()), FieldCompletionState.complete);
    });

    test('a date value is complete', () {
      expect(_classify(_date()), FieldCompletionState.complete);
    });

    test('a signature value is complete', () {
      expect(_classify(_signature()), FieldCompletionState.complete);
    });

    test('a null value with ok validation is optional-empty', () {
      expect(_classify(null), FieldCompletionState.optionalEmpty);
    });
  });

  group('blocking validation error', () {
    test('an error wins over a non-empty value', () {
      final FieldCompletionState state = _classify(
        _text('invoice 42'),
        validation: _error(),
      );

      expect(state, FieldCompletionState.blockingError);
      expect(state.isBlocking, isTrue);
      expect(state.countsAsComplete, isFalse);
    });

    test('an error wins over a null value', () {
      expect(
        _classify(null, validation: _error()),
        FieldCompletionState.blockingError,
      );
    });

    test('an error wins over an unchecked checkbox', () {
      expect(
        _classify(_checkbox(checked: false), validation: _error()),
        FieldCompletionState.blockingError,
      );
    });
  });

  group('warning precedence', () {
    test('a warning overrides a non-empty value', () {
      final FieldCompletionState state = _classify(
        _text('invoice 42'),
        validation: _warning(),
      );

      expect(state, FieldCompletionState.warning);
      expect(state.isBlocking, isFalse);
      expect(state.countsAsComplete, isTrue);
    });

    test('a warning overrides a null value', () {
      expect(
        _classify(null, validation: _warning()),
        FieldCompletionState.warning,
      );
    });

    test('an empty optional text with a warning is warning, not empty', () {
      final core.TextValue empty = _text('   ');

      expect(_classify(empty), FieldCompletionState.optionalEmpty);
      expect(
        _classify(empty, validation: _warning()),
        FieldCompletionState.warning,
      );
    });

    test('a warning overrides an unchecked checkbox', () {
      expect(
        _classify(_checkbox(checked: false), validation: _warning()),
        FieldCompletionState.warning,
      );
    });
  });

  group('incompatible content', () {
    test('non-empty preserved text with ok validation is incompatible', () {
      final FieldCompletionState state = _classify(
        _incompatible(preservedText: 'kept text'),
      );

      expect(state, FieldCompletionState.incompatible);
      expect(state.isBlocking, isTrue);
      expect(state.countsAsComplete, isFalse);
    });

    test('empty preserved text is still incompatible', () {
      expect(
        _classify(_incompatible(preservedText: '')),
        FieldCompletionState.incompatible,
      );
    });

    test('incompatible content wins over a warning', () {
      expect(
        _classify(_incompatible(), validation: _warning()),
        FieldCompletionState.incompatible,
      );
    });

    test('a blocking error wins over incompatible content', () {
      expect(
        _classify(_incompatible(), validation: _error()),
        FieldCompletionState.blockingError,
      );
    });
  });

  group('extension semantics', () {
    test(
      'every state maps to the exact blocking and completion predicates',
      () {
        const Map<FieldCompletionState, (bool, bool)> expected =
            <FieldCompletionState, (bool, bool)>{
              FieldCompletionState.complete: (false, true),
              FieldCompletionState.optionalEmpty: (false, true),
              FieldCompletionState.warning: (false, true),
              FieldCompletionState.blockingError: (true, false),
              FieldCompletionState.incompatible: (true, false),
            };

        for (final MapEntry<FieldCompletionState, (bool, bool)> entry
            in expected.entries) {
          expect(
            entry.key.isBlocking,
            entry.value.$1,
            reason: '${entry.key.name}.isBlocking',
          );
          expect(
            entry.key.countsAsComplete,
            entry.value.$2,
            reason: '${entry.key.name}.countsAsComplete',
          );
        }
      },
    );
  });

  group('production source purity', () {
    test('imports only the core model and writes no user-facing text', () {
      final File file = File(
        '${packageRoot.path}/lib/features/editor/field_completion.dart',
      );
      expect(file.existsSync(), isTrue);

      final String source = file.readAsStringSync();
      final List<String> imports = RegExp(
        r"^import '([^']+)'",
        multiLine: true,
      ).allMatches(source).map((Match match) => match.group(1)!).toList();

      expect(imports, <String>['package:feldexa_core/feldexa_core.dart']);
      expect(source, isNot(contains('package:flutter')));
      expect(source, isNot(contains('AppLocalizations')));
      expect(source, isNot(contains('dart:io')));
      expect(source, isNot(contains('dart:convert')));
      expect(
        RegExp(r'[\u00e4\u00f6\u00fc\u00c4\u00d6\u00dc\u00df]')
            .hasMatch(source),
        isFalse,
      );
    });
  });
}
