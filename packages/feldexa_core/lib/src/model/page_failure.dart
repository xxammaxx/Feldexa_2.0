// Feldexa page-failure value object (T017).
//
// Owner: `packages/feldexa_core/lib/src/model/page_failure.dart` (T017).
// Normative sources:
//   * `data-model.md` §3.3 — `pageIndex`, `category`
//     (`rasterization | unreadable | unsupported_structure`), and `messageKey`
//     (German catalog key);
//   * `contracts/ports.md` §2.1 — the one canonical `PageFailure` shape used by
//     port signatures;
//   * `contracts/recognition-output.md` §4 — failed pages stay isolated and
//     never remove suggestions from other pages.
//
// This file deliberately contains no OCR or recognition-envelope fields such
// as `recoverable` or `suggestionCount`; those belong to T057's per-page
// recognition envelope. `messageKey` is a catalog key, never a German sentence
// and never document content.
library;

import 'canonical_json.dart';

/// The three page-failure categories owned by the core model.
///
/// `contracts/recognition-output.md` §4 also names `ocr` and `internal`; those
/// are recognition-envelope failure categories, not the canonical core
/// `PageFailure` categories defined by `data-model.md` §3.3 and
/// `contracts/ports.md` §2.1. They are therefore not accepted here.
enum PageFailureCategory {
  /// The page could not be rendered for analysis.
  rasterization('rasterization'),

  /// The page content could not be decoded.
  unreadable('unreadable'),

  /// The page has no analyzable structure.
  unsupportedStructure('unsupported_structure');

  const PageFailureCategory(this.wireName);

  /// Stable JSON token.
  final String wireName;

  /// Parses a JSON token.
  ///
  /// Throws [FormatException] for a non-string or unknown token.
  static PageFailureCategory fromWire(Object? token) {
    if (token is String) {
      for (final PageFailureCategory value in values) {
        if (value.wireName == token) {
          return value;
        }
      }
    }
    throw const FormatException('Unknown page-failure category token.');
  }
}

/// A failed page's category and German catalog message key
/// (`data-model.md` §3.3).
///
/// A failure belongs to exactly one page. [PageFailure.pageIndex] must match
/// that page's index; the [Page] value object enforces that pairing and the
/// document aggregate enforces that the page exists. Unknown same-schema JSON
/// fields are retained across a read/write round (`data-model.md` §6).
final class PageFailure extends JsonObject {
  /// Creates a page failure.
  ///
  /// [pageIndex] must be non-negative and [messageKey] a stable German catalog
  /// key such as `IMP-006` or `REC-002`. [unknownFields] are opaque
  /// same-schema JSON extensions retained for a later write.
  ///
  /// Throws [ArgumentError] for every invalid value. The error never echoes
  /// document content.
  factory PageFailure({
    required int pageIndex,
    required PageFailureCategory category,
    required String messageKey,
    Map<String, Object?> unknownFields = const <String, Object?>{},
  }) {
    if (pageIndex < 0) {
      throw ArgumentError('pageIndex must be at least 0');
    }
    if (!_catalogKeyPattern.hasMatch(messageKey)) {
      throw ArgumentError(
        'messageKey must be a German catalog key such as IMP-006',
      );
    }
    return PageFailure._(
      pageIndex: pageIndex,
      category: category,
      messageKey: messageKey,
      unknownFields: freezeUnknownJsonFields(unknownFields),
    );
  }

  const PageFailure._({
    required this.pageIndex,
    required this.category,
    required this.messageKey,
    required super.unknownFields,
  });

  /// Reads a persisted page failure.
  ///
  /// Unknown same-schema keys are retained for a later write.
  ///
  /// Throws [FormatException] for missing, mistyped, or invalid fields.
  factory PageFailure.fromJson(Map<String, Object?> json) {
    final Object? pageIndex = json['pageIndex'];
    if (pageIndex is! int) {
      throw const FormatException('JSON field "pageIndex" must be an integer');
    }
    final Object? messageKey = json['messageKey'];
    if (messageKey is! String) {
      throw const FormatException('JSON field "messageKey" must be a string');
    }
    try {
      return PageFailure(
        pageIndex: pageIndex,
        category: PageFailureCategory.fromWire(json['category']),
        messageKey: messageKey,
        unknownFields: unknownJsonFields(json, _pageFailureJsonKeys),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid page failure JSON: ${error.message}');
    }
  }

  /// Zero-based page index of the failed page.
  final int pageIndex;

  /// Why the page failed.
  final PageFailureCategory category;

  /// German catalog key resolved to text at the UI boundary.
  final String messageKey;

  /// Returns a copy with the supplied fields replaced.
  ///
  /// The result is revalidated by the public constructor.
  PageFailure copyWith({
    int? pageIndex,
    PageFailureCategory? category,
    String? messageKey,
    Map<String, Object?>? unknownFields,
  }) {
    return PageFailure(
      pageIndex: pageIndex ?? this.pageIndex,
      category: category ?? this.category,
      messageKey: messageKey ?? this.messageKey,
      unknownFields: unknownFields ?? this.unknownFields,
    );
  }

  /// Serializes to the persisted failure object.
  Map<String, Object?> toJson() {
    return toJsonWithUnknown(<String, Object?>{
      'pageIndex': pageIndex,
      'category': category.wireName,
      'messageKey': messageKey,
    });
  }

  @override
  bool operator ==(Object other) {
    return other is PageFailure &&
        other.pageIndex == pageIndex &&
        other.category == category &&
        other.messageKey == messageKey;
  }

  @override
  int get hashCode => Object.hash(pageIndex, category, messageKey);

  @override
  String toString() {
    return 'PageFailure(pageIndex: $pageIndex, '
        'category: ${category.wireName})';
  }
}

/// German catalog keys are compact stable codes such as `IMP-006`.
final RegExp _catalogKeyPattern = RegExp(r'^[A-Z]{2,6}-[0-9]{3}$');

/// Modeled keys of a persisted page failure.
const Set<String> _pageFailureJsonKeys = <String>{
  'pageIndex',
  'category',
  'messageKey',
};
