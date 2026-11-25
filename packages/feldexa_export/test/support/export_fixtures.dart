// Shared host-VM fixtures for the T103/T113/T102 export tests.
//
// The layout and plan tests measure real German values against the bundled
// Noto Sans advance table, so they load `apps/feldexa_app/assets/fonts/
// metrics.json` from the repository instead of hard-coding a path. The
// package root is located by pubspec name, so the tests run both from
// `packages/feldexa_export` and from the repository root.
library;

import 'dart:io';

import 'package:feldexa_core/feldexa_core.dart';
import 'package:feldexa_export/feldexa_export.dart';

/// Repository-relative location of this package.
const String _repositoryPath = 'packages/feldexa_export';

/// Pubspec name that identifies this package.
const String _packageName = 'feldexa_export';

/// The `feldexa_export` package directory.
final Directory packageRoot = _locatePackageRoot();

/// The repository root that contains the package.
final Directory repositoryRoot = packageRoot.parent.parent;

const String metricsRelativePath = 'apps/feldexa_app/assets/fonts/metrics.json';
const String sourceSha256 =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

/// Reads the bundled metrics table as the layout engine receives it.
ExportFontMetrics loadBundledMetrics() {
  final File file = File('${repositoryRoot.path}/$metricsRelativePath');
  if (!file.existsSync()) {
    throw StateError(
      'Metrics bundle not found at ${file.path}; run the test from the '
      'repository.',
    );
  }
  return ExportFontMetrics.decode(file.readAsStringSync());
}

/// UTC timestamp used by every fixture.
DateTime at([int minute = 0]) => DateTime.utc(2026, 11, 20, 9, minute);

/// A lowercase UUIDv4 fixture derived from [value].
String uuid(int value) {
  return '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
}

/// A4 portrait page geometry in display space.
PageGeometry a4({int rotation = 0}) {
  return PageGeometry(
    mediaBox: Rect.fromLTWH(0, 0, 595.28, 841.89),
    rotation: rotation,
  );
}

/// A confirmed field on [pageIndex] at display [rect].
ConfirmedField confirmedField({
  required String id,
  required FieldType type,
  required Rect rect,
  int pageIndex = 0,
  String label = 'Feld',
  int order = 0,
  Provenance provenance = Provenance.user,
  FieldValidation validation = FieldValidation.ok,
}) {
  return ConfirmedField(
    id: id,
    pageIndex: pageIndex,
    rect: rect,
    type: type,
    provenance: provenance,
    label: label,
    order: order,
    createdAt: at(),
    updatedAt: at(),
    validation: validation,
  );
}

/// A text value fixture.
TextValue textValue(String text) => TextValue(text: text, lastEditedAt: at());

/// A multiline value fixture.
MultilineValue multilineValue(String text) =>
    MultilineValue(text: text, lastEditedAt: at());

/// A checkbox value fixture.
CheckboxValue checkboxValue({bool checked = true}) =>
    CheckboxValue(checked: checked, lastEditedAt: at());

/// A German number value fixture; [canonical] uses the stored dot decimal.
NumberValue numberValue(String canonical, {String? rawGerman}) => NumberValue(
  canonical: canonical,
  rawGerman: rawGerman ?? canonical.replaceAll('.', ','),
  lastEditedAt: at(),
);

/// A canonical date value fixture.
DateValue dateValue(String canonical) =>
    DateValue(canonical: canonical, lastEditedAt: at());

/// A signature value fixture.
SignatureValue signatureValue(String assetId) =>
    SignatureValue(signatureAssetId: assetId, lastEditedAt: at());

/// A signature capture fixture with [widthPx]×[heightPx] source pixels.
SignatureMark signatureMark({
  required String assetId,
  required String fieldId,
  required Rect fieldRect,
  int widthPx = 200,
  int heightPx = 100,
  int pageIndex = 0,
}) {
  return SignatureMark(
    assetId: assetId,
    fieldId: fieldId,
    pageIndex: pageIndex,
    rect: fieldRect,
    widthPx: widthPx,
    heightPx: heightPx,
    capturedAt: at(),
    sha256: sourceSha256,
  );
}

/// Builds a document snapshot from [fields] and their content.
///
/// [pageGeometry] describes every page; it defaults to A4 portrait.
Document buildDocument({
  required Iterable<ConfirmedField> fields,
  Map<String, FieldValue> values = const <String, FieldValue>{},
  Map<String, SignatureMark> signatures = const <String, SignatureMark>{},
  Iterable<FieldSuggestion> suggestions = const <FieldSuggestion>[],
  int pageCount = 1,
  PageGeometry? pageGeometry,
}) {
  final List<ConfirmedField> ordered = fields.toList(growable: false);
  final PageGeometry geometry = pageGeometry ?? a4();
  return Document(
    id: uuid(1),
    title: 'Formular',
    createdAt: at(),
    updatedAt: at(),
    source: SourceFileRef(
      id: uuid(2),
      sha256: sourceSha256,
      sizeBytes: 1024,
      pageCount: pageCount,
      importedAt: at(),
    ),
    pages: <Page>[
      for (int index = 0; index < pageCount; index++)
        Page(index: index, geometry: geometry),
    ],
    suggestions: suggestions,
    fields: ordered,
    fieldOrder: <String>[for (final ConfirmedField field in ordered) field.id],
    values: values,
    signatures: signatures,
    lastDurable: DurablePointer(
      revisionId: uuid(3),
      kind: 'autosave',
      committedAt: at(),
      sha256: sourceSha256,
    ),
  );
}

/// An unresolved machine suggestion on page [pageIndex].
FieldSuggestion suggestion({
  required int ordinal,
  int pageIndex = 0,
  SuggestionResolution resolution = SuggestionResolution.unresolved,
}) {
  return FieldSuggestion(
    id: 's_p${pageIndex}_${ordinal.toString().padLeft(4, '0')}',
    pageIndex: pageIndex,
    rect: Rect.fromLTWH(40, 40, 120, 20),
    proposedType: FieldType.text,
    confidence: 0.9,
    labelText: null,
    evidence: SuggestionEvidence(
      cues: <SuggestionCue>[SuggestionCue.underline],
      contrast: EvidenceContrast.normal,
      ocrUsed: true,
    ),
    resolution: resolution,
  );
}

Directory _locatePackageRoot() {
  Directory directory = Directory.current.absolute;
  while (true) {
    for (final Directory candidate in <Directory>[
      directory,
      Directory('${directory.path}/$_repositoryPath'),
    ]) {
      if (_isPackage(candidate)) {
        return candidate;
      }
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not locate $_repositoryPath (pubspec name: $_packageName) from '
        '${Directory.current.absolute.path}.',
      );
    }
    directory = parent;
  }
}

bool _isPackage(Directory directory) {
  final File pubspec = File('${directory.path}/pubspec.yaml');
  return pubspec.existsSync() &&
      pubspec.readAsStringSync().contains('name: $_packageName');
}
