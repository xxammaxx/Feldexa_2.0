// T032 evidence report validator.
//
// Validates an evidence report against `tools/evaluation/report_schema.json`
// and the rules in `specs/001-scanned-form-workflow/reports/README.md`
// (constitution Principle VIII, spec.md §Evidence and Verification Rules).
//
// The validator parses the Markdown report template into the normalized model
// described by the JSON Schema, applies the standard JSON Schema keywords used
// by the schema (no third-party dependency), and then checks the semantic
// rules that JSON Schema cannot express: one class per report, status
// consistency, class-specific environment evidence, performance conditions,
// privacy, artifact bytes/hashes, self-reference, naming, and the index row.
//
// Usage:
//   dart tools/evaluation/validate_report.dart <report.md> [...]
//   dart tools/evaluation/validate_report.dart --schema-check
//   dart tools/evaluation/validate_report.dart --json <report.md>
//
// Options:
//   --schema PATH              Report schema (default: beside this script).
//   --root PATH                Repository root (default: discovered from cwd).
//   --json                     Emit machine-readable JSON.
//   --schema-check             Validate only the schema, then exit.
//   --no-index                 Do not require the report's README index row.
//   --no-git                   Do not verify the base commit with git.
//   --no-layout                Accept a report outside the evidence root.
//   --allow-missing-artifacts  Downgrade absent artifact files to warnings.
//
// Exit codes: 0 all reports valid, 1 invalid report, 2 usage/schema error.
//
// This is host-only tooling. It produces no SIMULATED, EMULATOR, or DEVICE
// evidence.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String _draft202012 = 'https://json-schema.org/draft/2020-12/schema';

const Set<String> _supportedSchemaKeywords = <String>{
  r'$schema',
  r'$id',
  r'$ref',
  r'$defs',
  r'$comment',
  'title',
  'description',
  'type',
  'additionalProperties',
  'required',
  'properties',
  'enum',
  'const',
  'pattern',
  'minLength',
  'maxLength',
  'minimum',
  'maximum',
  'exclusiveMinimum',
  'exclusiveMaximum',
  'items',
  'minItems',
  'maxItems',
  'default',
  'examples',
  'deprecated',
  'readOnly',
  'writeOnly',
};

/// A single validation finding. Messages never echo untrusted report content.
class ValidationIssue {
  const ValidationIssue(this.code, this.message, {this.location});

  final String code;
  final String message;
  final String? location;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (location != null) 'location': location,
  };

  @override
  String toString() {
    final String prefix = location == null ? '' : '$location: ';
    return '[$code] $prefix$message';
  }
}

/// Validation outcome for one report.
class ReportValidation {
  ReportValidation(
    this.path, {
    required List<ValidationIssue> errors,
    required List<ValidationIssue> warnings,
  }) : errors = List<ValidationIssue>.unmodifiable(errors),
       warnings = List<ValidationIssue>.unmodifiable(warnings);

  final String path;
  final List<ValidationIssue> errors;
  final List<ValidationIssue> warnings;

  bool get valid => errors.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'valid': valid,
    'errors': errors.map((ValidationIssue issue) => issue.toJson()).toList(),
    'warnings': warnings
        .map((ValidationIssue issue) => issue.toJson())
        .toList(),
  };
}

class _UsageException implements Exception {
  const _UsageException(this.message);
  final String message;
}

class SchemaException implements Exception {
  const SchemaException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SectionDefinition {
  const SectionDefinition(this.key, this.title);
  final String key;
  final String title;
}

class PerformanceRules {
  const PerformanceRules({
    required this.noClaim,
    required this.conditionGroups,
    required this.sc004Triggers,
    required this.sc004Required,
  });

  final String noClaim;
  final List<PerformanceConditionGroup> conditionGroups;
  final List<String> sc004Triggers;
  final List<String> sc004Required;
}

class PerformanceConditionGroup {
  const PerformanceConditionGroup(this.name, this.anyOf);
  final String name;
  final List<String> anyOf;
}

class PrivacyRules {
  const PrivacyRules({
    required this.forbiddenSubstrings,
    required this.forbiddenPatterns,
  });

  final List<String> forbiddenSubstrings;
  final List<PrivacyPattern> forbiddenPatterns;
}

class PrivacyPattern {
  const PrivacyPattern(this.name, this.pattern);
  final String name;
  final RegExp pattern;
}

/// Parsed and self-checked `report_schema.json`.
class ReportSchema {
  ReportSchema._({
    required this.document,
    required this.schemaId,
    required this.evidenceRoot,
    required this.indexFile,
    required this.fileNamePattern,
    required this.titleSeparator,
    required this.metadataLabels,
    required this.sectionOrder,
    required this.tableHeaders,
    required this.classEnvironment,
    required this.deviceEquivalence,
    required this.runtimeMarkers,
    required this.performance,
    required this.privacy,
    required this.authorMustLeaveBlank,
  });

  final Map<String, Object?> document;
  final String schemaId;
  final String evidenceRoot;
  final String indexFile;
  final RegExp fileNamePattern;
  final String titleSeparator;
  final Map<String, String> metadataLabels;
  final List<SectionDefinition> sectionOrder;
  final Map<String, List<String>> tableHeaders;
  final Map<String, List<String>> classEnvironment;
  final List<String> deviceEquivalence;
  final Map<String, List<String>> runtimeMarkers;
  final PerformanceRules performance;
  final PrivacyRules privacy;
  final bool authorMustLeaveBlank;

  factory ReportSchema.load(File file) {
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FileSystemException catch (error) {
      throw SchemaException('cannot read report schema: ${error.message}');
    } on FormatException catch (error) {
      throw SchemaException(
        'report schema is not valid JSON: ${error.message}',
      );
    }
    final Map<String, Object?>? maybeSchema = _asMap(decoded);
    if (maybeSchema == null) {
      throw const SchemaException('report schema root must be a JSON object');
    }
    final Map<String, Object?> schema = maybeSchema;
    if (schema[r'$schema'] != _draft202012) {
      throw SchemaException(
        r'report schema must declare $schema ' + _draft202012,
      );
    }
    final String schemaId = _requiredString(schema, r'$id', 'schema');
    _checkSchemaKeywords(schema, r'$');

    final Map<String, Object?> defs = _requiredMap(schema, r'$defs', 'schema');
    for (final String name in <String>[
      'title',
      'metadata',
      'sections',
      'check',
      'artifact',
      'reviewRow',
      'dirtyFile',
      'sha256',
      'date',
      'evidenceClass',
      'result',
      'checkOutcome',
      'sectionBody',
    ]) {
      if (!defs.containsKey(name)) {
        throw SchemaException(r'missing $defs.' + name);
      }
    }

    final Map<String, Object?> markdown = _requiredMap(
      schema,
      'x-markdown',
      'schema',
    );
    final String evidenceRoot = _requiredString(
      markdown,
      'evidenceRoot',
      'x-markdown',
    );
    final String indexFile = _requiredString(
      markdown,
      'indexFile',
      'x-markdown',
    );
    final RegExp fileNamePattern = _compilePattern(
      _requiredString(markdown, 'fileNamePattern', 'x-markdown'),
      'x-markdown.fileNamePattern',
    );
    final String titleSeparator = _requiredString(
      markdown,
      'titleSeparator',
      'x-markdown',
    );

    final Map<String, Object?> labels = _requiredMap(
      markdown,
      'metadataLabels',
      'x-markdown',
    );
    final Map<String, String> metadataLabels = <String, String>{};
    for (final String key in <String>[
      'evidenceClass',
      'result',
      'taskIssue',
      'timestamp',
      'revision',
      'externalAttestation',
      'buildIdentity',
      'toolchain',
      'input',
    ]) {
      metadataLabels[key] = _requiredString(labels, key, 'metadataLabels');
    }
    if (metadataLabels.values.toSet().length != metadataLabels.length) {
      throw const SchemaException('metadata labels must be unique');
    }

    final List<SectionDefinition> sectionOrder = <SectionDefinition>[];
    final Object? rawSections = markdown['sectionOrder'];
    if (rawSections is! List) {
      throw const SchemaException('x-markdown.sectionOrder must be an array');
    }
    for (final Object? raw in rawSections) {
      final Map<String, Object?>? entry = _asMap(raw);
      if (entry == null) {
        throw const SchemaException(
          'x-markdown.sectionOrder entries must be objects',
        );
      }
      sectionOrder.add(
        SectionDefinition(
          _requiredString(entry, 'key', 'sectionOrder'),
          _requiredString(entry, 'title', 'sectionOrder'),
        ),
      );
    }
    if (sectionOrder.length != 11) {
      throw const SchemaException(
        'x-markdown.sectionOrder must contain the eleven template sections',
      );
    }
    final Map<String, Object?> sectionsSchema = _requiredMap(
      defs,
      'sections',
      r'$defs',
    );
    final Object? requiredSections = sectionsSchema['required'];
    if (requiredSections is! List ||
        requiredSections.whereType<String>().toSet().length !=
            sectionOrder.length ||
        !sectionOrder.every(
          (SectionDefinition section) => requiredSections.contains(section.key),
        )) {
      throw const SchemaException(
        r'$defs.sections.required must match x-markdown.sectionOrder',
      );
    }

    final Map<String, Object?> rawHeaders = _requiredMap(
      markdown,
      'tableHeaders',
      'x-markdown',
    );
    final Map<String, List<String>> tableHeaders = <String, List<String>>{};
    for (final String table in <String>['checks', 'artifacts', 'review']) {
      final Object? raw = rawHeaders[table];
      if (raw is! List ||
          raw.isEmpty ||
          raw.any((Object? item) => item is! String)) {
        throw SchemaException(
          'x-markdown.tableHeaders.$table must be an array',
        );
      }
      tableHeaders[table] = raw.cast<String>();
    }

    final Map<String, Object?> rawClassEnvironment = _requiredMap(
      markdown,
      'classEnvironment',
      'x-markdown',
    );
    final Map<String, List<String>> classEnvironment = <String, List<String>>{};
    for (final String className in <String>[
      'SIMULATED',
      'EMULATOR',
      'DEVICE',
      'NONE',
    ]) {
      final Map<String, Object?>? entry = _asMap(
        rawClassEnvironment[className],
      );
      if (entry == null) {
        throw SchemaException('missing x-markdown.classEnvironment.$className');
      }
      classEnvironment[className] = _requiredStringList(
        entry,
        'required',
        'classEnvironment.$className',
      );
    }

    final Map<String, Object?> equivalence = _requiredMap(
      markdown,
      'deviceEquivalence',
      'x-markdown',
    );
    final List<String> deviceEquivalence = _requiredStringList(
      equivalence,
      'required',
      'deviceEquivalence',
    );

    final Map<String, Object?> rawMarkers = _requiredMap(
      markdown,
      'runtimeMarkers',
      'x-markdown',
    );
    final Map<String, List<String>> runtimeMarkers = <String, List<String>>{
      'SIMULATED': _requiredStringList(
        rawMarkers,
        'SIMULATED',
        'runtimeMarkers',
      ),
      'ANDROID': _requiredStringList(rawMarkers, 'ANDROID', 'runtimeMarkers'),
    };

    final Map<String, Object?> rawPerformance = _requiredMap(
      markdown,
      'performance',
      'x-markdown',
    );
    final String noClaim = _requiredString(
      rawPerformance,
      'noClaim',
      'performance',
    );
    final Object? rawGroups = rawPerformance['conditionGroups'];
    if (rawGroups is! List || rawGroups.isEmpty) {
      throw const SchemaException(
        'x-markdown.performance.conditionGroups must be a non-empty array',
      );
    }
    final List<PerformanceConditionGroup> groups =
        <PerformanceConditionGroup>[];
    for (final Object? raw in rawGroups) {
      final Map<String, Object?>? group = _asMap(raw);
      if (group == null) {
        throw const SchemaException(
          'performance.conditionGroups entries must be objects',
        );
      }
      groups.add(
        PerformanceConditionGroup(
          _requiredString(group, 'name', 'conditionGroups'),
          _requiredStringList(group, 'any', 'conditionGroups'),
        ),
      );
    }
    final Map<String, Object?> sc004 = _requiredMap(
      rawPerformance,
      'sc004',
      'performance',
    );
    final PerformanceRules performance = PerformanceRules(
      noClaim: noClaim,
      conditionGroups: groups,
      sc004Triggers: _requiredStringList(sc004, 'triggers', 'sc004'),
      sc004Required: _requiredStringList(sc004, 'required', 'sc004'),
    );

    final Map<String, Object?> rawPrivacy = _requiredMap(
      markdown,
      'privacy',
      'x-markdown',
    );
    final List<String> forbiddenSubstrings = _requiredStringList(
      rawPrivacy,
      'forbiddenSubstrings',
      'privacy',
    );
    final Object? rawPatterns = rawPrivacy['forbiddenPatterns'];
    if (rawPatterns is! List || rawPatterns.isEmpty) {
      throw const SchemaException(
        'x-markdown.privacy.forbiddenPatterns must be a non-empty array',
      );
    }
    final List<PrivacyPattern> forbiddenPatterns = <PrivacyPattern>[];
    for (final Object? raw in rawPatterns) {
      final Map<String, Object?>? entry = _asMap(raw);
      if (entry == null) {
        throw const SchemaException('privacy patterns must be objects');
      }
      forbiddenPatterns.add(
        PrivacyPattern(
          _requiredString(entry, 'name', 'privacy'),
          _compilePattern(
            _requiredString(entry, 'pattern', 'privacy'),
            'privacy.forbiddenPatterns',
          ),
        ),
      );
    }
    final PrivacyRules privacy = PrivacyRules(
      forbiddenSubstrings: forbiddenSubstrings,
      forbiddenPatterns: forbiddenPatterns,
    );

    final Map<String, Object?> review = _requiredMap(
      markdown,
      'review',
      'x-markdown',
    );
    final Object? blank = review['authorMustLeaveBlank'];
    if (blank is! bool) {
      throw const SchemaException(
        'x-markdown.review.authorMustLeaveBlank must be a boolean',
      );
    }

    return ReportSchema._(
      document: schema,
      schemaId: schemaId,
      evidenceRoot: evidenceRoot,
      indexFile: indexFile,
      fileNamePattern: fileNamePattern,
      titleSeparator: titleSeparator,
      metadataLabels: metadataLabels,
      sectionOrder: sectionOrder,
      tableHeaders: tableHeaders,
      classEnvironment: classEnvironment,
      deviceEquivalence: deviceEquivalence,
      runtimeMarkers: runtimeMarkers,
      performance: performance,
      privacy: privacy,
      authorMustLeaveBlank: blank,
    );
  }
}

/// Validate one evidence report.
ReportValidation validateReport({
  required File report,
  required ReportSchema schema,
  required Directory root,
  bool checkIndex = true,
  bool verifyArtifacts = true,
  bool allowMissingArtifacts = false,
  bool verifyGit = true,
  bool checkLayout = true,
}) {
  final List<ValidationIssue> errors = <ValidationIssue>[];
  final List<ValidationIssue> warnings = <ValidationIssue>[];
  final String displayPath = _displayReportPath(report, root);

  String text;
  Uint8List bytes;
  try {
    bytes = report.readAsBytesSync();
    text = utf8.decode(bytes);
  } on FileSystemException {
    errors.add(const ValidationIssue('io.report', 'cannot read report'));
    return ReportValidation(
      _reportBasename(report),
      errors: _dedupe(errors),
      warnings: _dedupe(warnings),
    );
  } on FormatException {
    errors.add(
      const ValidationIssue('io.encoding', 'report is not valid UTF-8'),
    );
    return ReportValidation(
      _reportBasename(report),
      errors: _dedupe(errors),
      warnings: _dedupe(warnings),
    );
  }

  final _ReportParser parser = _ReportParser(text, schema);
  final Map<String, Object?> model = parser.parse();
  final String? relativePath = _relativePath(report, root);

  errors.addAll(_validateInstance(model, schema.document, schema.document));
  errors.addAll(parser.issues);

  final Map<String, Object?> title = _mapOrEmpty(model['title']);
  final Map<String, Object?> metadata = _mapOrEmpty(model['metadata']);
  final Map<String, Object?> sections = _mapOrEmpty(model['sections']);
  final List<Object?> checks = _listOrEmpty(model['checks']);
  final List<Object?> artifacts = _listOrEmpty(model['artifacts']);
  final List<Object?> review = _listOrEmpty(model['review']);

  final String titleClass = _stringOrEmpty(title['evidenceClass']);
  final String metadataClass = _stringOrEmpty(metadata['evidenceClass']);
  final String result = _stringOrEmpty(metadata['result']);
  final String evidenceClass = metadataClass.isEmpty
      ? titleClass
      : metadataClass;

  if (titleClass.isNotEmpty &&
      metadataClass.isNotEmpty &&
      titleClass != metadataClass) {
    errors.add(
      ValidationIssue(
        'class.mismatch',
        'title class $titleClass does not match metadata class '
            '$metadataClass; every report has exactly one class',
      ),
    );
  }

  _checkNaming(
    errors: errors,
    schema: schema,
    relativePath: relativePath,
    title: title,
    metadata: metadata,
    evidenceClass: evidenceClass,
    checkLayout: checkLayout,
  );
  _checkDateTime(errors: errors, title: title, metadata: metadata);
  _checkEnvironment(
    errors: errors,
    schema: schema,
    sections: sections,
    evidenceClass: evidenceClass,
  );
  _checkRuntimeMarkers(
    errors: errors,
    schema: schema,
    checks: checks,
    evidenceClass: evidenceClass,
  );
  _checkStatus(errors: errors, result: result, checks: checks);
  _checkCheckExitCodes(errors: errors, checks: checks);
  _checkPerformance(
    errors: errors,
    schema: schema,
    sections: sections,
    evidenceClass: evidenceClass,
  );
  _checkMetadataContent(errors: errors, metadata: metadata);
  _checkPrivacy(errors: errors, schema: schema, text: text);
  _checkSelfReference(
    errors: errors,
    text: text,
    bytes: bytes,
    artifacts: artifacts,
    relativePath: relativePath,
  );
  _checkArtifacts(
    errors: errors,
    warnings: warnings,
    root: root,
    artifacts: artifacts,
    relativePath: relativePath,
    verifyArtifacts: verifyArtifacts,
    allowMissingArtifacts: allowMissingArtifacts,
  );
  _checkCheckLogs(errors: errors, checks: checks, artifacts: artifacts);
  _checkDirtyFiles(
    errors: errors,
    root: root,
    metadata: metadata,
    relativePath: relativePath,
    verifyArtifacts: verifyArtifacts,
  );
  _checkReview(errors: errors, review: review, schema: schema);
  if (checkIndex) {
    _checkIndex(
      errors: errors,
      schema: schema,
      root: root,
      relativePath: relativePath,
      evidenceClass: evidenceClass,
    );
  }
  if (verifyGit) {
    _checkGit(
      errors: errors,
      warnings: warnings,
      root: root,
      metadata: metadata,
    );
  }

  return ReportValidation(
    displayPath,
    errors: _dedupe(errors),
    warnings: _dedupe(warnings),
  );
}

List<ValidationIssue> _validateInstance(
  Object? instance,
  Object? schemaNode,
  Map<String, Object?> rootSchema,
) {
  final List<ValidationIssue> errors = <ValidationIssue>[];
  _validateNode(instance, schemaNode, rootSchema, r'$', errors);
  return errors;
}

void _validateNode(
  Object? instance,
  Object? schemaNode,
  Map<String, Object?> rootSchema,
  String path,
  List<ValidationIssue> errors,
) {
  if (schemaNode is bool) {
    if (!schemaNode) {
      _addSchemaError(errors, path, 'instance is rejected by a false schema');
    }
    return;
  }
  final Map<String, Object?>? schema = _asMap(schemaNode);
  if (schema == null) {
    _addSchemaError(errors, path, 'schema node is not an object');
    return;
  }

  final Object? ref = schema[r'$ref'];
  if (ref != null) {
    if (ref is! String) {
      _addSchemaError(errors, path, r'$ref must be a string');
    } else {
      final Map<String, Object?>? resolved = _resolveRef(ref, rootSchema);
      if (resolved == null) {
        _addSchemaError(errors, path, 'unresolved reference $ref');
      } else {
        _validateNode(instance, resolved, rootSchema, path, errors);
      }
    }
  }

  final Object? typeNode = schema['type'];
  if (typeNode != null) {
    final List<String> types = typeNode is List
        ? typeNode.whereType<String>().toList()
        : typeNode is String
        ? <String>[typeNode]
        : <String>[];
    if (types.isEmpty) {
      _addSchemaError(errors, path, 'schema type must be a string or array');
    } else if (!types.any((String type) => _matchesType(instance, type))) {
      _addSchemaError(
        errors,
        path,
        'expected ${types.join(' or ')}, found ${_typeName(instance)}',
      );
      return;
    }
  }

  final Object? enumNode = schema['enum'];
  if (enumNode is List) {
    if (!enumNode.any((Object? allowed) => _deepEquals(instance, allowed))) {
      _addSchemaError(
        errors,
        path,
        'value is not one of ${enumNode.map(_renderValue).join(', ')}',
      );
    }
  }

  if (schema.containsKey('const') && !_deepEquals(instance, schema['const'])) {
    _addSchemaError(errors, path, 'value does not match const');
  }

  if (instance is String) {
    final Object? pattern = schema['pattern'];
    if (pattern is String) {
      try {
        if (!RegExp(pattern).hasMatch(instance)) {
          _addSchemaError(errors, path, 'value does not match pattern');
        }
      } on FormatException {
        _addSchemaError(errors, path, 'schema pattern is not a valid regex');
      }
    }
    final Object? minLength = schema['minLength'];
    if (minLength is int && instance.length < minLength) {
      _addSchemaError(
        errors,
        path,
        'value is shorter than $minLength characters',
      );
    }
    final Object? maxLength = schema['maxLength'];
    if (maxLength is int && instance.length > maxLength) {
      _addSchemaError(
        errors,
        path,
        'value is longer than $maxLength characters',
      );
    }
  }

  if (instance is num) {
    final Object? minimum = schema['minimum'];
    if (minimum is num && instance < minimum) {
      _addSchemaError(errors, path, 'value is less than $minimum');
    }
    final Object? maximum = schema['maximum'];
    if (maximum is num && instance > maximum) {
      _addSchemaError(errors, path, 'value is greater than $maximum');
    }
    final Object? exclusiveMinimum = schema['exclusiveMinimum'];
    if (exclusiveMinimum is num && instance <= exclusiveMinimum) {
      _addSchemaError(
        errors,
        path,
        'value must be greater than $exclusiveMinimum',
      );
    }
    final Object? exclusiveMaximum = schema['exclusiveMaximum'];
    if (exclusiveMaximum is num && instance >= exclusiveMaximum) {
      _addSchemaError(
        errors,
        path,
        'value must be less than $exclusiveMaximum',
      );
    }
  }

  if (instance is List) {
    final Object? minItems = schema['minItems'];
    if (minItems is int && instance.length < minItems) {
      _addSchemaError(errors, path, 'array has fewer than $minItems items');
    }
    final Object? maxItems = schema['maxItems'];
    if (maxItems is int && instance.length > maxItems) {
      _addSchemaError(errors, path, 'array has more than $maxItems items');
    }
    final Object? items = schema['items'];
    if (items != null) {
      for (int index = 0; index < instance.length; index++) {
        _validateNode(
          instance[index],
          items,
          rootSchema,
          '$path[$index]',
          errors,
        );
      }
    }
  }

  if (instance is Map<String, Object?>) {
    final Object? required = schema['required'];
    if (required is List) {
      for (final Object? key in required) {
        if (key is String && !instance.containsKey(key)) {
          _addSchemaError(errors, path, 'missing required property "$key"');
        }
      }
    }
    final Map<String, Object?>? properties = _asMap(schema['properties']);
    final Object? additional = schema['additionalProperties'];
    if (properties != null) {
      for (final MapEntry<String, Object?> entry in properties.entries) {
        if (instance.containsKey(entry.key)) {
          _validateNode(
            instance[entry.key],
            entry.value,
            rootSchema,
            '$path.${entry.key}',
            errors,
          );
        }
      }
    }
    for (final String key in instance.keys) {
      if (properties != null && properties.containsKey(key)) {
        continue;
      }
      if (additional == false) {
        _addSchemaError(errors, path, 'unexpected property "$key"');
      } else if (additional is Map<String, Object?> || additional is bool) {
        _validateNode(
          instance[key],
          additional,
          rootSchema,
          '$path.$key',
          errors,
        );
      }
    }
  }
}

void _addSchemaError(
  List<ValidationIssue> errors,
  String path,
  String message,
) {
  errors.add(ValidationIssue('schema', '$path: $message'));
}

Map<String, Object?>? _resolveRef(String ref, Map<String, Object?> root) {
  if (!ref.startsWith('#/')) {
    return null;
  }
  Object? current = root;
  for (final String raw in ref.substring(2).split('/')) {
    final String segment = raw.replaceAll('~1', '/').replaceAll('~0', '~');
    if (current is Map<String, Object?>) {
      current = current[segment];
    } else if (current is List) {
      final int? index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) {
        return null;
      }
      current = current[index];
    } else {
      return null;
    }
  }
  return _asMap(current);
}

void _checkSchemaKeywords(Object? node, String path) {
  if (node is! Map<String, Object?>) {
    return;
  }
  for (final MapEntry<String, Object?> entry in node.entries) {
    final String key = entry.key;
    if (key.startsWith('x-')) {
      continue;
    }
    if (!_supportedSchemaKeywords.contains(key)) {
      throw SchemaException('unsupported JSON Schema keyword "$key" at $path');
    }
    if (key == 'pattern') {
      final Object? value = entry.value;
      if (value is! String) {
        throw SchemaException('pattern at $path must be a string');
      }
      _compilePattern(value, '$path.pattern');
    } else if (key == 'type') {
      final Object? value = entry.value;
      final Iterable<String> types = value is String
          ? <String>[value]
          : value is List
          ? value.whereType<String>()
          : const <String>[];
      if (types.isEmpty ||
          types.any(
            (String type) => !const <String>{
              'object',
              'array',
              'string',
              'integer',
              'number',
              'boolean',
              'null',
            }.contains(type),
          )) {
        throw SchemaException('unsupported type at $path');
      }
    } else if (key == 'enum') {
      final Object? value = entry.value;
      if (value is! List || value.isEmpty) {
        throw SchemaException('enum at $path must be a non-empty array');
      }
    } else if (key == 'required') {
      final Object? value = entry.value;
      if (value is! List || value.any((Object? item) => item is! String)) {
        throw SchemaException('required at $path must be a string array');
      }
    } else if (key == r'$ref' && entry.value is! String) {
      throw SchemaException(r'$ref at $path must be a string');
    }
    if (key == r'$defs' || key == 'properties') {
      final Map<String, Object?>? children = _asMap(entry.value);
      if (children != null) {
        for (final MapEntry<String, Object?> child in children.entries) {
          _checkSchemaKeywords(child.value, '$path/$key/${child.key}');
        }
      }
    } else if (key == 'items' || key == 'additionalProperties') {
      _checkSchemaKeywords(entry.value, '$path/$key');
    }
  }
}

class _ReportParser {
  _ReportParser(this.text, this.schema) {
    final Map<String, Object?> sectionValues = <String, Object?>{};
    for (final SectionDefinition section in schema.sectionOrder) {
      sectionValues[section.key] = '';
    }
    model = <String, Object?>{
      'title': <String, Object?>{
        'date': '',
        'evidenceClass': '',
        'summary': '',
      },
      'metadata': <String, Object?>{
        'evidenceClass': '',
        'result': '',
        'task': '',
        'issue': 0,
        'timestamp': '',
        'date': '',
        'baseCommit': '',
        'treeState': '',
        'externalAttestation': '',
        'buildIdentity': '',
        'toolchain': '',
        'input': '',
      },
      'sections': sectionValues,
      'checks': <Object?>[],
      'artifacts': <Object?>[],
      'review': <Object?>[],
    };
  }

  final String text;
  final ReportSchema schema;
  final List<ValidationIssue> issues = <ValidationIssue>[];
  late final Map<String, Object?> model;
  late final List<String> lines = const LineSplitter().convert(text);
  final Map<String, String> _sectionBodies = <String, String>{};
  int _titleIndex = -1;

  Map<String, Object?> parse() {
    _parseTitle();
    _parseMetadata();
    _parseSections();
    _parseChecks();
    _parseArtifacts();
    _parseReview();
    return model;
  }

  void _add(String code, String message) {
    if (issues.any(
      (ValidationIssue issue) => issue.code == code && issue.message == message,
    )) {
      return;
    }
    issues.add(ValidationIssue(code, message));
  }

  void _parseTitle() {
    for (int index = 0; index < lines.length; index++) {
      final String line = lines[index].trim();
      if (line.isEmpty) {
        continue;
      }
      _titleIndex = index;
      final String pattern =
          '^#\\s+([0-9]{4}-[0-9]{2}-[0-9]{2})\\s+'
          '(SIMULATED|EMULATOR|DEVICE|NONE)'
          '${RegExp.escape(schema.titleSeparator)}(\\S.*)\$';
      final RegExpMatch? match = RegExp(pattern).firstMatch(line);
      if (match == null) {
        _add(
          'parse.title',
          'title must be "# <YYYY-MM-DD> <CLASS>${schema.titleSeparator}<summary>"',
        );
        return;
      }
      final Map<String, Object?> title = _mapOrEmpty(model['title']);
      title['date'] = match.group(1);
      title['evidenceClass'] = match.group(2);
      title['summary'] = match.group(3)!.trim();
      model['title'] = title;
      return;
    }
    _add('parse.title', 'report has no title line');
  }

  void _parseMetadata() {
    final _Table? table = _findTableAfter(_titleIndex + 1);
    if (table == null) {
      _add('parse.metadata', 'missing Field/Value metadata table');
      return;
    }
    if (!_headerMatches(table.header, <String>['Field', 'Value'])) {
      _add(
        'parse.metadata',
        'metadata table must have Field and Value columns',
      );
      return;
    }
    final Set<String> allowedLabels = schema.metadataLabels.values.toSet();
    final Map<String, String> values = <String, String>{};
    for (final List<String> row in table.rows) {
      if (row.length < 2) {
        _add('parse.metadata', 'metadata row has fewer than two cells');
        continue;
      }
      final String key = row[0].trim();
      final String value = row[1].trim();
      if (key.isEmpty) {
        _add('parse.metadata', 'metadata row has an empty field name');
        continue;
      }
      if (!allowedLabels.contains(key)) {
        _add(
          'parse.metadata.unknown',
          'metadata table contains a field that is not in the template',
        );
      }
      if (values.containsKey(key)) {
        _add('parse.metadata', 'metadata table contains a duplicate field');
      }
      values[key] = value;
      if (_hasPlaceholder(key) || _hasPlaceholder(value)) {
        _add('parse.placeholder', 'metadata table contains a placeholder');
      }
    }

    for (final String key in schema.metadataLabels.values) {
      if (!values.containsKey(key)) {
        _add(
          'parse.metadata.missing',
          'missing required metadata field "$key"',
        );
      }
    }

    final Map<String, Object?> metadata = _mapOrEmpty(model['metadata']);
    final String? classValue = _strictEnum(
      values[schema.metadataLabels['evidenceClass']],
      const <String>['SIMULATED', 'EMULATOR', 'DEVICE', 'NONE'],
    );
    if (classValue != null) {
      metadata['evidenceClass'] = classValue;
    } else if (values.containsKey(schema.metadataLabels['evidenceClass'])) {
      _add(
        'parse.metadata',
        'Evidence class must be exactly SIMULATED, EMULATOR, DEVICE, or NONE',
      );
    }

    final String? resultValue = _strictEnum(
      values[schema.metadataLabels['result']],
      const <String>['PASS', 'FAIL', 'PARTIAL'],
    );
    if (resultValue != null) {
      metadata['result'] = resultValue;
    } else if (values.containsKey(schema.metadataLabels['result'])) {
      _add(
        'parse.metadata',
        'Result must be exactly PASS, FAIL, or PARTIAL with no qualifier',
      );
    }

    final String? taskIssue = values[schema.metadataLabels['taskIssue']];
    if (taskIssue != null) {
      final RegExpMatch? match = RegExp(r'^T([0-9]{3})\s*/\s*#([0-9]+)$')
          .firstMatch(_stripBackticks(taskIssue));
      if (match == null) {
        _add('parse.metadata', 'Task / issue must look like "T032 / #32"');
      } else {
        metadata['task'] = 'T${match.group(1)}';
        metadata['issue'] = int.parse(match.group(2)!);
      }
    }

    final String timestamp = _cleanValue(
      values[schema.metadataLabels['timestamp']],
    );
    metadata['timestamp'] = timestamp;
    final RegExpMatch? timestampMatch = RegExp(
      r'^([0-9]{4}-[0-9]{2}-[0-9]{2}) ([0-9]{2}:[0-9]{2}) Europe/Berlin$',
    ).firstMatch(timestamp);
    if (timestampMatch == null) {
      _add(
        'parse.metadata',
        'Date / timezone must look like "2026-11-13 11:30 Europe/Berlin"',
      );
    } else {
      metadata['date'] = timestampMatch.group(1);
    }

    _parseRevision(
      metadata: metadata,
      value: values[schema.metadataLabels['revision']],
    );

    metadata['externalAttestation'] = _cleanValue(
      values[schema.metadataLabels['externalAttestation']],
    );
    metadata['buildIdentity'] = _cleanValue(
      values[schema.metadataLabels['buildIdentity']],
    );
    metadata['toolchain'] = _cleanValue(
      values[schema.metadataLabels['toolchain']],
    );
    metadata['input'] = _cleanValue(values[schema.metadataLabels['input']]);

    if (_stringOrEmpty(metadata['externalAttestation']).isEmpty) {
      _add('parse.metadata', 'External attestation must not be empty');
    }
    if (_stringOrEmpty(metadata['buildIdentity']).isEmpty) {
      _add('parse.metadata', 'Build identity must not be empty');
    }
    if (_stringOrEmpty(metadata['toolchain']).isEmpty) {
      _add('parse.metadata', 'Toolchain must not be empty');
    }
    if (_stringOrEmpty(metadata['input']).isEmpty) {
      _add('parse.metadata', 'Input must not be empty');
    }

    model['metadata'] = metadata;
  }

  void _parseRevision({
    required Map<String, Object?> metadata,
    required String? value,
  }) {
    if (value == null) {
      return;
    }
    final String cleaned = _stripBackticks(value);
    final RegExpMatch? base = RegExp(
      r'base commit\s+`?([0-9a-f]{40})`?',
      caseSensitive: false,
    ).firstMatch(value);
    if (base == null) {
      _add('parse.metadata', 'Revision must name the full base commit SHA');
    } else {
      metadata['baseCommit'] = base.group(1);
    }

    final RegExpMatch? tree = RegExp(
      r'tree\s+`?(clean|dirty)`?',
      caseSensitive: false,
    ).firstMatch(value);
    if (tree == null) {
      _add('parse.metadata', 'Revision must state tree "clean" or "dirty"');
    } else {
      metadata['treeState'] = tree.group(1)!.toLowerCase();
    }

    final List<Object?> dirtyFiles = <Object?>[];
    final RegExp dirtyPattern = RegExp(
      r'`([^`]+)`\s*(?:\(|:)?\s*SHA-256\s*`?([0-9a-f]{64})`?',
      caseSensitive: false,
    );
    for (final RegExpMatch match in dirtyPattern.allMatches(value)) {
      dirtyFiles.add(<String, Object?>{
        'path': match.group(1)!.trim(),
        'sha256': match.group(2),
      });
    }
    if (dirtyFiles.isNotEmpty) {
      metadata['dirtyFiles'] = dirtyFiles;
    }

    if (cleaned.contains('candidate') && !cleaned.contains('attestation')) {
      _add(
        'parse.metadata',
        'Candidate SHA must be recorded in the external attestation, not asserted in the report',
      );
    }
  }

  void _parseSections() {
    final List<_Section> sections = <_Section>[];
    for (int index = 0; index < lines.length; index++) {
      final RegExpMatch? match = RegExp(r'^##\s+([0-9]+)\.\s+(.+?)\s*$')
          .firstMatch(lines[index]);
      if (match == null) {
        continue;
      }
      final int number = int.parse(match.group(1)!);
      final String heading = match.group(2)!.trim();
      int end = lines.length;
      for (int next = index + 1; next < lines.length; next++) {
        if (RegExp(r'^##\s+').hasMatch(lines[next])) {
          end = next;
          break;
        }
      }
      sections.add(_Section(number, heading, index, end));
      index = end - 1;
    }

    if (sections.isEmpty) {
      _add('parse.sections', 'report has no numbered sections');
      return;
    }

    final Map<String, Object?> modelSections = _mapOrEmpty(model['sections']);
    for (final _Section section in sections) {
      if (section.number < 1 || section.number > schema.sectionOrder.length) {
        _add(
          'parse.sections',
          'section number ${section.number} is outside the template',
        );
        continue;
      }
      final SectionDefinition expected =
          schema.sectionOrder[section.number - 1];
      final String heading = section.heading.toLowerCase();
      if (!heading.startsWith(expected.title.toLowerCase())) {
        _add(
          'parse.sections',
          'section ${section.number} must be "${expected.title}"',
        );
      }
      final String body = lines
          .sublist(section.start + 1, section.end)
          .join('\n')
          .trim();
      if (modelSections.containsKey(expected.key) &&
          _stringOrEmpty(modelSections[expected.key]).isNotEmpty) {
        _add(
          'parse.sections',
          'duplicate section ${section.number} (${expected.title})',
        );
      }
      modelSections[expected.key] = body;
      _sectionBodies[expected.key] = body;
    }
    for (final SectionDefinition expected in schema.sectionOrder) {
      if (!_sectionBodies.containsKey(expected.key)) {
        _add(
          'parse.sections.missing',
          'missing required section "${expected.title}"',
        );
      } else if (_sectionBodies[expected.key]!.trim().isEmpty) {
        _add('parse.sections', 'section "${expected.title}" is empty');
      }
    }
    model['sections'] = modelSections;
  }

  void _parseChecks() {
    final List<String> body = _bodyLines('checks');
    final _Table? table = _findTableWithHeader(
      body,
      schema.tableHeaders['checks']!,
    );
    if (table == null) {
      _add(
        'parse.checks',
        'missing checks table with columns ${schema.tableHeaders['checks']!.join(', ')}',
      );
      return;
    }
    final List<Object?> checks = <Object?>[];
    int expectedIndex = 1;
    for (final List<String> row in table.rows) {
      if (row.every((String cell) => cell.trim().isEmpty)) {
        continue;
      }
      if (row.length < 5) {
        _add('parse.checks', 'check row has fewer than five cells');
        continue;
      }
      final int? index = int.tryParse(_cleanValue(row[0]));
      if (index == null) {
        _add('parse.checks', 'check index is not an integer');
      } else if (index != expectedIndex) {
        _add('parse.checks', 'check indexes must be sequential starting at 1');
      }
      expectedIndex++;

      final String commandCell = row[1].trim();
      final RegExpMatch? commandMatch = RegExp(r'^(.*?)\s*\(([^()]*)\)\s*$')
          .firstMatch(commandCell);
      String command = commandCell;
      String cwd = '';
      if (commandMatch != null) {
        command = commandMatch.group(1)!.trim();
        cwd = commandMatch.group(2)!.trim();
      } else {
        _add(
          'parse.checks',
          'check row must place its working directory in parentheses',
        );
      }
      command = _cleanValue(command);
      cwd = _cleanValue(cwd);
      if (cwd == 'root' || cwd == '<repo-root>') {
        cwd = '.';
      }
      if (command.isEmpty) {
        _add('parse.checks', 'check command is empty');
      }
      if (_hasPlaceholder(command) || _hasPlaceholder(cwd)) {
        _add('parse.checks', 'check command or cwd contains a placeholder');
      }

      final String? outcome = _strictEnum(_cleanValue(row[4]), const <String>[
        'PASS',
        'FAIL',
        'PARTIAL',
        'UNAVAILABLE',
        'ABSENT',
      ]);
      if (outcome == null) {
        _add(
          'parse.checks',
          'check outcome must be PASS, FAIL, PARTIAL, UNAVAILABLE, or ABSENT',
        );
      }

      final String exitText = _cleanValue(row[2]);
      final bool notRun = outcome == 'UNAVAILABLE' || outcome == 'ABSENT';
      int? exitCode;
      if (notRun &&
          const <String>{
            '-',
            'n/a',
            'na',
            'not run',
            '',
          }.contains(exitText.toLowerCase())) {
        exitCode = null;
      } else {
        exitCode = int.tryParse(exitText.replaceAll(RegExp(r'[<>]'), ''));
        if (exitCode == null) {
          _add('parse.checks', 'check exit code is not an integer');
        }
      }

      final String log = _cleanValue(row[3]);
      if (log.isEmpty) {
        _add('parse.checks', 'check log cell is empty');
      }
      if (_hasPlaceholder(log) &&
          log.toLowerCase() != 'console only (not retained)') {
        _add('parse.checks', 'check log contains a placeholder');
      }

      checks.add(<String, Object?>{
        'index': index ?? 0,
        'command': command,
        'cwd': cwd,
        'exitCode': exitCode,
        'log': log,
        'outcome': outcome ?? '',
      });
    }
    if (checks.isEmpty) {
      _add('parse.checks', 'checks table has no rows');
    }
    model['checks'] = checks;
  }

  void _parseArtifacts() {
    final List<String> body = _bodyLines('artifacts');
    final _Table? table = _findTableWithHeader(
      body,
      schema.tableHeaders['artifacts']!,
    );
    if (table == null) {
      _add(
        'parse.artifacts',
        'missing artifacts table with columns ${schema.tableHeaders['artifacts']!.join(', ')}',
      );
      return;
    }
    final List<Object?> artifacts = <Object?>[];
    final Set<String> paths = <String>{};
    for (final List<String> row in table.rows) {
      if (row.every((String cell) => cell.trim().isEmpty)) {
        continue;
      }
      if (row.length < 4) {
        _add('parse.artifacts', 'artifact row has fewer than four cells');
        continue;
      }
      if (row.length > 4 &&
          row.sublist(4).any((String cell) => cell.trim().isNotEmpty)) {
        _add('parse.artifacts', 'artifact row has extra non-empty cells');
      }
      final String name = _cleanValue(row[0]);
      final String path = _cleanValue(row[1]);
      final int? bytes = int.tryParse(_cleanValue(row[2]));
      final String sha256 = _cleanValue(row[3]).toLowerCase();
      if (name.isEmpty) {
        _add('parse.artifacts', 'artifact name is empty');
      }
      if (_hasPlaceholder(name) || _hasPlaceholder(path)) {
        _add('parse.artifacts', 'artifact row contains a placeholder');
      }
      if (path.isEmpty) {
        _add('parse.artifacts', 'artifact path is empty');
      }
      if (!paths.add(path)) {
        _add('parse.artifacts', 'artifacts table contains a duplicate path');
      }
      if (bytes == null) {
        _add('parse.artifacts', 'artifact bytes are not an integer');
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
        _add(
          'parse.artifacts',
          'artifact SHA-256 must be 64 lowercase hex characters',
        );
      }
      artifacts.add(<String, Object?>{
        'name': name,
        'path': path,
        'bytes': bytes ?? 0,
        'sha256': sha256,
      });
    }
    model['artifacts'] = artifacts;
  }

  void _parseReview() {
    final List<String> body = _bodyLines('independentReview');
    final _Table? table = _findTableWithHeader(
      body,
      schema.tableHeaders['review']!,
    );
    if (table == null) {
      _add(
        'parse.review',
        'missing review table with columns ${schema.tableHeaders['review']!.join(', ')}',
      );
      return;
    }
    final List<Object?> review = <Object?>[];
    for (final List<String> row in table.rows) {
      if (row.length < 4) {
        _add('parse.review', 'review row has fewer than four cells');
        continue;
      }
      final String reviewer = _cleanValue(row[0]);
      final String date = _cleanValue(row[1]);
      final String verdict = _cleanValue(row[2]);
      final String notes = _cleanValue(row[3]);
      if (schema.authorMustLeaveBlank &&
          <String>[
            reviewer,
            date,
            verdict,
            notes,
          ].any((String value) => value.isNotEmpty)) {
        _add(
          'parse.review',
          'the author must leave the independent-review row blank',
        );
      }
      review.add(<String, Object?>{
        'reviewer': reviewer,
        'date': date,
        'verdict': verdict,
        'notes': notes,
      });
    }
    if (review.isEmpty) {
      _add('parse.review', 'review table has no row');
    }
    model['review'] = review;
  }

  List<String> _bodyLines(String key) {
    final String body = _sectionBodies[key] ?? '';
    return body.isEmpty ? <String>[] : const LineSplitter().convert(body);
  }

  _Table? _findTableAfter(int start) {
    for (int index = start; index < lines.length; index++) {
      if (lines[index].trim().startsWith('|')) {
        return _readTable(lines, index);
      }
      if (lines[index].startsWith('## ')) {
        return null;
      }
    }
    return null;
  }

  _Table? _findTableWithHeader(List<String> body, List<String> expected) {
    for (int index = 0; index < body.length; index++) {
      if (!body[index].trim().startsWith('|')) {
        continue;
      }
      final _Table? table = _readTable(body, index);
      if (table != null && _headerMatches(table.header, expected)) {
        return table;
      }
    }
    return null;
  }

  _Table? _readTable(List<String> source, int start) {
    final List<List<String>> rows = <List<String>>[];
    int index = start;
    while (index < source.length && source[index].trim().startsWith('|')) {
      rows.add(_splitRow(source[index]));
      index++;
    }
    if (rows.length < 2 || !_isSeparator(rows[1])) {
      return null;
    }
    return _Table(rows[0], rows.sublist(2));
  }
}

class _Table {
  const _Table(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;
}

class _Section {
  const _Section(this.number, this.heading, this.start, this.end);
  final int number;
  final String heading;
  final int start;
  final int end;
}

List<String> _splitRow(String line) {
  String value = line.trim();
  if (value.startsWith('|')) {
    value = value.substring(1);
  }
  if (value.endsWith('|')) {
    value = value.substring(0, value.length - 1);
  }
  final List<String> cells = <String>[];
  final StringBuffer current = StringBuffer();
  bool escaped = false;
  for (final int codeUnit in value.codeUnits) {
    final String character = String.fromCharCode(codeUnit);
    if (escaped) {
      current.write(character);
      escaped = false;
    } else if (character == r'\') {
      escaped = true;
    } else if (character == '|') {
      cells.add(current.toString().trim());
      current.clear();
    } else {
      current.write(character);
    }
  }
  cells.add(current.toString().trim());
  return cells;
}

bool _isSeparator(List<String> cells) {
  return cells.isNotEmpty &&
      cells.every(
        (String cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell.trim()),
      );
}

bool _headerMatches(List<String> actual, List<String> expected) {
  if (actual.length < expected.length) {
    return false;
  }
  for (int index = 0; index < expected.length; index++) {
    if (_normalizeHeader(actual[index]) != _normalizeHeader(expected[index])) {
      return false;
    }
  }
  return true;
}

String _normalizeHeader(String value) {
  return _stripBackticks(value).toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _stripBackticks(String value) {
  return value.replaceAll('`', '').trim();
}

String _cleanValue(String? value) {
  if (value == null) {
    return '';
  }
  return _stripBackticks(value).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _strictEnum(String? value, List<String> allowed) {
  if (value == null) {
    return null;
  }
  final String cleaned = _stripBackticks(value);
  return allowed.contains(cleaned) ? cleaned : null;
}

bool _hasPlaceholder(String value) {
  return RegExp(r'<[^>]+>').hasMatch(value);
}

void _checkNaming({
  required List<ValidationIssue> errors,
  required ReportSchema schema,
  required String? relativePath,
  required Map<String, Object?> title,
  required Map<String, Object?> metadata,
  required String evidenceClass,
  required bool checkLayout,
}) {
  if (relativePath == null) {
    if (checkLayout) {
      errors.add(
        const ValidationIssue(
          'naming.root',
          'report is outside the repository root',
        ),
      );
    }
    return;
  }
  if (checkLayout && !relativePath.startsWith('${schema.evidenceRoot}/')) {
    errors.add(
      ValidationIssue(
        'naming.root',
        'report must live under ${schema.evidenceRoot}/',
      ),
    );
  }
  final String baseName = relativePath.split('/').last;
  if (baseName == schema.indexFile) {
    return;
  }
  final RegExpMatch? match = schema.fileNamePattern.firstMatch(baseName);
  if (match == null) {
    errors.add(
      const ValidationIssue(
        'naming.file',
        'report file name must be YYYY-MM-DD-<slug>.md with a lowercase slug',
      ),
    );
    return;
  }
  final String date = match.namedGroup('date') ?? '';
  final String slug = match.namedGroup('slug') ?? '';
  final String titleDate = _stringOrEmpty(title['date']);
  final String metadataDate = _stringOrEmpty(metadata['date']);
  if (titleDate.isNotEmpty && date != titleDate) {
    errors.add(
      const ValidationIssue(
        'naming.date',
        'file-name date does not match the title date',
      ),
    );
  }
  if (metadataDate.isNotEmpty && date != metadataDate) {
    errors.add(
      const ValidationIssue(
        'naming.date',
        'file-name date does not match the Date / timezone date',
      ),
    );
  }
  if (evidenceClass == 'NONE') {
    final RegExpMatch? taskMatch = RegExp(r'(?:^|-)t([0-9]{3})(?:-|$)')
        .firstMatch(slug);
    if (taskMatch == null) {
      errors.add(
        const ValidationIssue(
          'naming.task',
          'NONE task-provenance reports must include tNNN in the file name',
        ),
      );
    } else {
      final String task = _stringOrEmpty(metadata['task']);
      if (task.isNotEmpty && task != 'T${taskMatch.group(1)}') {
        errors.add(
          const ValidationIssue(
            'naming.task',
            'file-name task does not match the Task / issue field',
          ),
        );
      }
    }
  } else if (!slug.startsWith('${evidenceClass.toLowerCase()}-')) {
    errors.add(
      ValidationIssue(
        'naming.class',
        'class-run reports must be named YYYY-MM-DD-'
            '${evidenceClass.toLowerCase()}-<slug>.md',
      ),
    );
  }
}

void _checkDateTime({
  required List<ValidationIssue> errors,
  required Map<String, Object?> title,
  required Map<String, Object?> metadata,
}) {
  final String titleDate = _stringOrEmpty(title['date']);
  if (titleDate.isNotEmpty && !_isCalendarDate(titleDate)) {
    errors.add(
      const ValidationIssue(
        'date.invalid',
        'title date is not a real calendar date',
      ),
    );
  }
  final String metadataDate = _stringOrEmpty(metadata['date']);
  if (metadataDate.isNotEmpty && !_isCalendarDate(metadataDate)) {
    errors.add(
      const ValidationIssue(
        'date.invalid',
        'reported date is not a real calendar date',
      ),
    );
  }
  final String timestamp = _stringOrEmpty(metadata['timestamp']);
  final RegExpMatch? match = RegExp(
    r'^([0-9]{4}-[0-9]{2}-[0-9]{2}) ([0-9]{2}):([0-9]{2}) Europe/Berlin$',
  ).firstMatch(timestamp);
  if (match == null) {
    return;
  }
  if (!_isCalendarDate(match.group(1)!)) {
    errors.add(
      const ValidationIssue(
        'timestamp.invalid',
        'timestamp date is not a real calendar date',
      ),
    );
  }
  final int hour = int.parse(match.group(2)!);
  final int minute = int.parse(match.group(3)!);
  if (hour > 23 || minute > 59) {
    errors.add(
      const ValidationIssue(
        'timestamp.invalid',
        'timestamp time is outside 00:00-23:59',
      ),
    );
  }
}

bool _isCalendarDate(String value) {
  final RegExpMatch? match = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$')
      .firstMatch(value);
  if (match == null) {
    return false;
  }
  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  if (year < 1 || month < 1 || month > 12 || day < 1) {
    return false;
  }
  return day <= DateTime.utc(year, month + 1, 0).day;
}

void _checkEnvironment({
  required List<ValidationIssue> errors,
  required ReportSchema schema,
  required Map<String, Object?> sections,
  required String evidenceClass,
}) {
  final String environment = _stringOrEmpty(sections['environment'])
      .toLowerCase();
  if (environment.isEmpty) {
    return;
  }
  if (_hasPlaceholder(environment)) {
    errors.add(
      const ValidationIssue(
        'class.environment',
        'environment block contains a placeholder',
      ),
    );
  }
  final Map<String, bool> classBlocks = <String, bool>{
    for (final String className in <String>['SIMULATED', 'EMULATOR', 'DEVICE'])
      className: RegExp(
        '\\b$className\\s*:',
        caseSensitive: false,
      ).hasMatch(environment),
  };
  final List<String> present = classBlocks.entries
      .where((MapEntry<String, bool> entry) => entry.value)
      .map((MapEntry<String, bool> entry) => entry.key)
      .toList();
  if (evidenceClass == 'NONE' && present.isNotEmpty) {
    errors.add(
      const ValidationIssue(
        'class.environment',
        'NONE environment must not contain a runtime class block',
      ),
    );
  } else if (evidenceClass != 'NONE' && evidenceClass.isNotEmpty) {
    if (!(classBlocks[evidenceClass] ?? false)) {
      errors.add(
        ValidationIssue(
          'class.environment',
          '$evidenceClass environment must contain its own class label',
        ),
      );
    }
    final List<String> others = present
        .where((String className) => className != evidenceClass)
        .toList();
    if (others.isNotEmpty) {
      errors.add(
        ValidationIssue(
          'class.environment',
          'environment contains multiple class blocks: '
              '${present.join(', ')}',
        ),
      );
    }
  }
  if (evidenceClass == 'DEVICE') {
    final List<String> required = schema.classEnvironment['DEVICE']!;
    final List<String> missing = required
        .where((String token) => !environment.contains(token))
        .toList();
    if (missing.isNotEmpty) {
      final bool equivalent = schema.deviceEquivalence.every(
        (String token) => environment.contains(token),
      );
      if (!equivalent) {
        errors.add(
          ValidationIssue(
            'class.environment',
            'DEVICE environment is missing: ${missing.join(', ')} '
                '(or a complete T141 equivalent)',
          ),
        );
      }
    }
    return;
  }
  final List<String>? required = schema.classEnvironment[evidenceClass];
  if (required == null) {
    return;
  }
  final List<String> missing = required
      .where((String token) => !environment.contains(token))
      .toList();
  if (missing.isNotEmpty) {
    errors.add(
      ValidationIssue(
        'class.environment',
        '$evidenceClass environment is missing: ${missing.join(', ')}',
      ),
    );
  }
}

void _checkRuntimeMarkers({
  required List<ValidationIssue> errors,
  required ReportSchema schema,
  required List<Object?> checks,
  required String evidenceClass,
}) {
  final String commands = checks
      .map((Object? check) => _stringOrEmpty(_mapOrEmpty(check)['command']))
      .join('\n')
      .toLowerCase();
  if (commands.isEmpty) {
    return;
  }
  bool hasAny(List<String> markers) =>
      markers.any((String marker) => commands.contains(marker));
  final bool simulated = hasAny(schema.runtimeMarkers['SIMULATED']!);
  final bool android = hasAny(schema.runtimeMarkers['ANDROID']!);
  if (evidenceClass == 'NONE') {
    if (simulated) {
      errors.add(
        const ValidationIssue(
          'class.runtime',
          'NONE report records a browser runtime command; that is SIMULATED evidence',
        ),
      );
    }
    if (android) {
      errors.add(
        const ValidationIssue(
          'class.runtime',
          'NONE report records an Android runtime command; that is EMULATOR or DEVICE evidence',
        ),
      );
    }
    return;
  }
  if (evidenceClass == 'SIMULATED' && android) {
    errors.add(
      const ValidationIssue(
        'class.runtime',
        'SIMULATED report records an Android runtime command and would merge classes',
      ),
    );
  }
  if ((evidenceClass == 'EMULATOR' || evidenceClass == 'DEVICE') && simulated) {
    errors.add(
      ValidationIssue(
        'class.runtime',
        '$evidenceClass report records a browser runtime command and would merge classes',
      ),
    );
  }
}

void _checkStatus({
  required List<ValidationIssue> errors,
  required String result,
  required List<Object?> checks,
}) {
  final List<String> outcomes = checks
      .map((Object? check) => _stringOrEmpty(_mapOrEmpty(check)['outcome']))
      .toList();
  if (result == 'PASS' && outcomes.any((String outcome) => outcome != 'PASS')) {
    errors.add(
      const ValidationIssue(
        'status.consistency',
        'PASS result has a non-PASS check; an incomplete run is PARTIAL or FAIL',
      ),
    );
  }
  if (result == 'FAIL' && !outcomes.contains('FAIL')) {
    errors.add(
      const ValidationIssue(
        'status.consistency',
        'FAIL result has no FAIL check',
      ),
    );
  }
  if (result == 'PARTIAL' &&
      outcomes.isNotEmpty &&
      outcomes.every((String outcome) => outcome == 'PASS')) {
    errors.add(
      const ValidationIssue(
        'status.consistency',
        'PARTIAL result has no partial, unavailable, absent, or failed check',
      ),
    );
  }
}

void _checkCheckExitCodes({
  required List<ValidationIssue> errors,
  required List<Object?> checks,
}) {
  for (final Object? raw in checks) {
    final Map<String, Object?> check = _mapOrEmpty(raw);
    final String outcome = _stringOrEmpty(check['outcome']);
    final int? exitCode = check['exitCode'] is int
        ? check['exitCode']! as int
        : null;
    if (outcome == 'PASS' && exitCode != 0) {
      errors.add(
        const ValidationIssue(
          'status.exitcode',
          'PASS check must record exit code 0',
        ),
      );
    } else if (outcome == 'FAIL' && (exitCode == null || exitCode == 0)) {
      errors.add(
        const ValidationIssue(
          'status.exitcode',
          'FAIL check must record a non-zero exit code',
        ),
      );
    } else if (outcome == 'PARTIAL' && exitCode == null) {
      errors.add(
        const ValidationIssue(
          'status.exitcode',
          'PARTIAL check must record an exit code',
        ),
      );
    } else if ((outcome == 'UNAVAILABLE' || outcome == 'ABSENT') &&
        exitCode != null) {
      errors.add(
        ValidationIssue(
          'status.exitcode',
          '$outcome check did not run and must record exit code "-"',
        ),
      );
    }
  }
}

bool _isNoPerformanceClaim(String text, String noClaim) {
  final String normalized = text
      .toLowerCase()
      .replaceAll(RegExp(r'[*_`]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final String phrase = noClaim.toLowerCase().trim();
  return normalized == phrase || normalized == '$phrase.';
}

void _checkPerformance({
  required List<ValidationIssue> errors,
  required ReportSchema schema,
  required Map<String, Object?> sections,
  required String evidenceClass,
}) {
  final String performance = _stringOrEmpty(sections['performance'])
      .toLowerCase();
  if (performance.isEmpty) {
    return;
  }
  if (_hasPlaceholder(performance)) {
    errors.add(
      const ValidationIssue(
        'performance.conditions',
        'performance section contains a placeholder',
      ),
    );
  }
  final bool exactNoClaim = _isNoPerformanceClaim(
    performance,
    schema.performance.noClaim,
  );
  if (exactNoClaim) {
    return;
  }
  final bool mentionsNoClaim = performance.contains(schema.performance.noClaim);
  final bool hasSchemaTrigger = schema.performance.sc004Triggers.any(
    performance.contains,
  );
  final RegExp timing = RegExp(
    r'\b[0-9]+(?:\.[0-9]+)?\s*(?:ms|s|seconds?|milliseconds?)\b',
  );
  final bool hasTiming = timing.hasMatch(performance) || hasSchemaTrigger;
  if (mentionsNoClaim && hasTiming) {
    errors.add(
      const ValidationIssue(
        'performance.contradiction',
        'performance section both disclaims and claims a timing result',
      ),
    );
  }
  if (evidenceClass == 'NONE' && hasTiming) {
    errors.add(
      const ValidationIssue(
        'performance.class',
        'NONE host checks cannot make a runtime performance claim',
      ),
    );
  }
  if (!hasTiming) {
    return;
  }
  for (final PerformanceConditionGroup group
      in schema.performance.conditionGroups) {
    if (!group.anyOf.any(performance.contains)) {
      errors.add(
        ValidationIssue(
          'performance.conditions',
          'performance claim is missing ${group.name}',
        ),
      );
    }
  }
  if (hasSchemaTrigger) {
    for (final String token in schema.performance.sc004Required) {
      if (!performance.contains(token)) {
        errors.add(
          ValidationIssue(
            'performance.sc004',
            'three-second claim is missing "$token"',
          ),
        );
      }
    }
  }
}

void _checkMetadataContent({
  required List<ValidationIssue> errors,
  required Map<String, Object?> metadata,
}) {
  for (final String key in <String>[
    'externalAttestation',
    'buildIdentity',
    'toolchain',
    'input',
  ]) {
    final String value = _stringOrEmpty(metadata[key]);
    if (_hasPlaceholder(value)) {
      errors.add(
        ValidationIssue(
          'metadata.placeholder',
          'metadata field contains a placeholder',
        ),
      );
    }
  }
  final String attestation = _stringOrEmpty(metadata['externalAttestation'])
      .toLowerCase();
  if (attestation.isNotEmpty &&
      !attestation.contains('attestation') &&
      !attestation.startsWith('refs/') &&
      !attestation.contains('bundle')) {
    errors.add(
      const ValidationIssue(
        'metadata.attestation',
        'External attestation must name a path, ref, bundle, or transport attestation',
      ),
    );
  }
  final String toolchain = _stringOrEmpty(metadata['toolchain']);
  if (toolchain.isNotEmpty && !toolchain.toLowerCase().contains('dart')) {
    errors.add(
      const ValidationIssue(
        'metadata.toolchain',
        'Toolchain must name the Dart version',
      ),
    );
  }
  final String input = _stringOrEmpty(metadata['input']).toLowerCase();
  if (input.isNotEmpty &&
      !input.contains('corpus') &&
      !input.contains('fixture') &&
      !input.contains('input') &&
      !input.contains('validator')) {
    errors.add(
      const ValidationIssue(
        'metadata.input',
        'Input must name the corpus, fixtures, or validator input',
      ),
    );
  }
  final String treeState = _stringOrEmpty(metadata['treeState']);
  final List<Object?> dirtyFiles = _listOrEmpty(metadata['dirtyFiles']);
  if (treeState == 'clean' && dirtyFiles.isNotEmpty) {
    errors.add(
      const ValidationIssue(
        'metadata.tree',
        'clean tree must not list dirty files',
      ),
    );
  }
  if (treeState == 'dirty' && dirtyFiles.isEmpty) {
    errors.add(
      const ValidationIssue(
        'metadata.tree',
        'dirty tree must list each changed file with its SHA-256',
      ),
    );
  }
}

void _checkPrivacy({
  required List<ValidationIssue> errors,
  required ReportSchema schema,
  required String text,
}) {
  final String lower = text.toLowerCase();
  for (final String forbidden in schema.privacy.forbiddenSubstrings) {
    if (lower.contains(forbidden.toLowerCase())) {
      errors.add(
        const ValidationIssue(
          'privacy.content',
          'report contains a forbidden absolute path, username, or transcript marker',
        ),
      );
    }
  }
  for (final PrivacyPattern pattern in schema.privacy.forbiddenPatterns) {
    if (pattern.pattern.hasMatch(text)) {
      errors.add(
        ValidationIssue(
          'privacy.content',
          'report contains a forbidden ${pattern.name}',
        ),
      );
    }
  }
}

void _checkSelfReference({
  required List<ValidationIssue> errors,
  required String text,
  required Uint8List bytes,
  required List<Object?> artifacts,
  required String? relativePath,
}) {
  final String digest = sha256Hex(bytes);
  if (text.toLowerCase().contains(digest)) {
    errors.add(
      const ValidationIssue(
        'self.reference',
        'report contains its own SHA-256; record it only in the external attestation',
      ),
    );
  }
  if (relativePath == null) {
    return;
  }
  final String normalizedReport = _normalizePath(relativePath);
  for (final Object? artifact in artifacts) {
    final String path = _normalizePath(
      _stringOrEmpty(_mapOrEmpty(artifact)['path']),
    );
    if (path == normalizedReport) {
      errors.add(
        const ValidationIssue(
          'self.reference',
          'report lists itself in the artifact table',
        ),
      );
    }
  }
}

void _checkCheckLogs({
  required List<ValidationIssue> errors,
  required List<Object?> checks,
  required List<Object?> artifacts,
}) {
  final Set<String> artifactPaths = artifacts
      .map(
        (Object? artifact) =>
            _normalizePath(_stringOrEmpty(_mapOrEmpty(artifact)['path'])),
      )
      .toSet();
  const Set<String> noLogLabels = <String>{
    'console only (not retained)',
    'none',
    'n/a',
    'not run',
    'no log',
  };
  for (final Object? raw in checks) {
    final Map<String, Object?> check = _mapOrEmpty(raw);
    final String outcome = _stringOrEmpty(check['outcome']);
    final String log = _cleanValue(_stringOrEmpty(check['log']));
    final String lower = log.toLowerCase();
    final bool noLogLabel = noLogLabels.contains(lower);
    if (outcome == 'UNAVAILABLE' || outcome == 'ABSENT') {
      if (!noLogLabel) {
        errors.add(
          ValidationIssue(
            'checks.log',
            '$outcome check must not name a retained log file',
          ),
        );
      }
      continue;
    }
    if (noLogLabel) {
      continue;
    }
    if (!_isSafeRelativePath(log)) {
      errors.add(
        const ValidationIssue(
          'checks.log',
          'retained check log must be a repository-relative path',
        ),
      );
      continue;
    }
    if (!artifactPaths.contains(_normalizePath(log))) {
      errors.add(
        const ValidationIssue(
          'checks.log',
          'retained check log is missing from the artifacts table',
        ),
      );
    }
  }
}

FileSystemEntityType _entityType(String path) {
  try {
    return FileSystemEntity.typeSync(path, followLinks: true);
  } on FileSystemException {
    return FileSystemEntityType.notFound;
  }
}

/// Returns the canonical target path when [entity] resolves inside [root].
///
/// Lexical checks alone are insufficient: a repository-relative path can be a
/// symbolic link to a file outside the repository. The canonical root and
/// target are compared with a separator boundary so `/repo-other` cannot pass
/// as a child of `/repo`.
String? _resolveWithinRoot(FileSystemEntity entity, Directory root) {
  try {
    final String rootResolved = _normalizePath(root.resolveSymbolicLinksSync());
    final String targetResolved = _normalizePath(
      entity.resolveSymbolicLinksSync(),
    );
    if (targetResolved == rootResolved) {
      return targetResolved;
    }
    final String prefix = rootResolved.endsWith('/')
        ? rootResolved
        : '$rootResolved/';
    return targetResolved.startsWith(prefix) ? targetResolved : null;
  } on FileSystemException {
    return null;
  }
}

void _checkArtifacts({
  required List<ValidationIssue> errors,
  required List<ValidationIssue> warnings,
  required Directory root,
  required List<Object?> artifacts,
  required String? relativePath,
  required bool verifyArtifacts,
  required bool allowMissingArtifacts,
}) {
  for (final Object? raw in artifacts) {
    final Map<String, Object?> artifact = _mapOrEmpty(raw);
    final String path = _normalizePath(_stringOrEmpty(artifact['path']));
    if (!_isSafeRelativePath(path)) {
      errors.add(
        const ValidationIssue(
          'artifact.path',
          'artifact path must be repository-relative and free of "..", "~", and backslashes',
        ),
      );
      continue;
    }
    if (!verifyArtifacts) {
      continue;
    }
    final File file = File('${root.path}/$path');
    final FileSystemEntityType type = _entityType(file.path);
    if (type == FileSystemEntityType.notFound) {
      if (allowMissingArtifacts) {
        warnings.add(
          ValidationIssue(
            'artifact.missing',
            'artifact file is absent (allowed for a fresh clone)',
          ),
        );
      } else {
        errors.add(
          ValidationIssue('artifact.missing', 'artifact file does not exist'),
        );
      }
      continue;
    }
    final String? resolved = _resolveWithinRoot(file, root);
    if (resolved == null) {
      errors.add(
        ValidationIssue(
          'artifact.symlink',
          'artifact path escapes the repository root through a symbolic link '
              'or cannot be resolved',
        ),
      );
      continue;
    }
    if (type == FileSystemEntityType.directory) {
      errors.add(
        ValidationIssue('artifact.type', 'artifact path is a directory'),
      );
      continue;
    }
    final Uint8List bytes;
    try {
      bytes = File(resolved).readAsBytesSync();
    } on FileSystemException {
      errors.add(
        ValidationIssue('artifact.read', 'artifact file cannot be read'),
      );
      continue;
    }
    final int expectedBytes = artifact['bytes'] is int
        ? artifact['bytes']! as int
        : -1;
    if (bytes.length != expectedBytes) {
      errors.add(
        ValidationIssue(
          'artifact.bytes',
          'artifact byte size differs from the report',
        ),
      );
    }
    final String expectedHash = _stringOrEmpty(artifact['sha256']);
    if (sha256Hex(bytes) != expectedHash) {
      errors.add(
        ValidationIssue(
          'artifact.hash',
          'artifact SHA-256 differs from the report',
        ),
      );
    }
  }
}

void _checkDirtyFiles({
  required List<ValidationIssue> errors,
  required Directory root,
  required Map<String, Object?> metadata,
  required String? relativePath,
  required bool verifyArtifacts,
}) {
  final List<Object?> dirtyFiles = _listOrEmpty(metadata['dirtyFiles']);
  if (_stringOrEmpty(metadata['treeState']) != 'dirty') {
    return;
  }
  for (final Object? raw in dirtyFiles) {
    final Map<String, Object?> file = _mapOrEmpty(raw);
    final String path = _normalizePath(_stringOrEmpty(file['path']));
    if (!_isSafeRelativePath(path)) {
      errors.add(
        const ValidationIssue(
          'metadata.tree',
          'dirty-file path must be repository-relative',
        ),
      );
      continue;
    }
    if (relativePath != null && _normalizePath(relativePath) == path) {
      errors.add(
        const ValidationIssue(
          'self.reference',
          'dirty-file list contains the report itself',
        ),
      );
      continue;
    }
    if (!verifyArtifacts) {
      continue;
    }
    final File actual = File('${root.path}/$path');
    final FileSystemEntityType type = _entityType(actual.path);
    if (type == FileSystemEntityType.notFound) {
      errors.add(
        ValidationIssue('metadata.tree', 'listed dirty file does not exist'),
      );
      continue;
    }
    final String? resolved = _resolveWithinRoot(actual, root);
    if (resolved == null) {
      errors.add(
        ValidationIssue(
          'metadata.tree',
          'dirty-file path escapes the repository root through a symbolic link '
              'or cannot be resolved',
        ),
      );
      continue;
    }
    if (type == FileSystemEntityType.directory) {
      errors.add(
        ValidationIssue(
          'metadata.tree',
          'dirty-file path is a directory, not a file',
        ),
      );
      continue;
    }
    final Uint8List bytes;
    try {
      bytes = File(resolved).readAsBytesSync();
    } on FileSystemException {
      errors.add(ValidationIssue('metadata.tree', 'dirty file cannot be read'));
      continue;
    }
    final String expected = _stringOrEmpty(file['sha256']);
    if (sha256Hex(bytes) != expected) {
      errors.add(
        ValidationIssue(
          'metadata.tree',
          'dirty-file SHA-256 differs from the recorded hash',
        ),
      );
    }
  }
}

void _checkReview({
  required List<ValidationIssue> errors,
  required List<Object?> review,
  required ReportSchema schema,
}) {
  if (!schema.authorMustLeaveBlank) {
    return;
  }
  for (final Object? raw in review) {
    final Map<String, Object?> row = _mapOrEmpty(raw);
    if (<String>[
      'reviewer',
      'date',
      'verdict',
      'notes',
    ].any((String key) => _stringOrEmpty(row[key]).isNotEmpty)) {
      errors.add(
        const ValidationIssue(
          'review.self',
          'author must leave the independent-review row blank; review is a separate record',
        ),
      );
    }
  }
}

void _checkIndex({
  required List<ValidationIssue> errors,
  required ReportSchema schema,
  required Directory root,
  required String? relativePath,
  required String evidenceClass,
}) {
  if (relativePath == null ||
      !relativePath.startsWith('${schema.evidenceRoot}/')) {
    return;
  }
  final String baseName = relativePath.split('/').last;
  if (baseName == schema.indexFile) {
    return;
  }
  final File index = File(
    '${root.path}/${schema.evidenceRoot}/${schema.indexFile}',
  );
  final FileSystemEntityType type = _entityType(index.path);
  if (type == FileSystemEntityType.notFound) {
    errors.add(
      const ValidationIssue(
        'index.missing',
        'evidence reports index README.md is missing',
      ),
    );
    return;
  }
  final String? resolved = _resolveWithinRoot(index, root);
  if (resolved == null) {
    errors.add(
      const ValidationIssue(
        'index.unreadable',
        'evidence reports index escapes the repository root or cannot be resolved',
      ),
    );
    return;
  }
  if (type == FileSystemEntityType.directory) {
    errors.add(
      const ValidationIssue(
        'index.unreadable',
        'evidence reports index is not a file',
      ),
    );
    return;
  }
  final List<String> lines;
  try {
    lines = File(resolved).readAsLinesSync();
  } on FileSystemException {
    errors.add(
      const ValidationIssue(
        'index.unreadable',
        'evidence reports index cannot be read',
      ),
    );
    return;
  }
  final Map<String, String> rows = _parseIndex(lines);
  if (!rows.containsKey(baseName)) {
    errors.add(
      ValidationIssue(
        'index.missing',
        'report is not listed in the evidence index',
      ),
    );
    return;
  }
  final String indexedClass = rows[baseName]!.toUpperCase();
  if (indexedClass.isNotEmpty &&
      indexedClass != evidenceClass &&
      indexedClass != '—') {
    errors.add(
      ValidationIssue(
        'index.class',
        'index class does not match the report class',
      ),
    );
  }
}

Map<String, String> _parseIndex(List<String> lines) {
  final Map<String, String> rows = <String, String>{};
  for (final String line in lines) {
    if (!line.trim().startsWith('| [')) {
      continue;
    }
    final List<String> cells = _splitRow(line);
    if (cells.length < 2) {
      continue;
    }
    final RegExpMatch? link = RegExp(r'\[[^\]]+\]\(\./([^)]+)\)')
        .firstMatch(cells[0]);
    if (link == null) {
      continue;
    }
    final String target = link.group(1)!.split('#').first;
    rows[target] = _stripBackticks(cells[1]);
  }
  return rows;
}

void _checkGit({
  required List<ValidationIssue> errors,
  required List<ValidationIssue> warnings,
  required Directory root,
  required Map<String, Object?> metadata,
}) {
  final String baseCommit = _stringOrEmpty(metadata['baseCommit']);
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(baseCommit)) {
    return;
  }
  if (!File('${root.path}/.git').existsSync() &&
      !Directory('${root.path}/.git').existsSync()) {
    return;
  }
  final ProcessResult exists = Process.runSync('git', <String>[
    '-C',
    root.path,
    'cat-file',
    '-e',
    '$baseCommit^{commit}',
  ]);
  if (exists.exitCode != 0) {
    errors.add(
      const ValidationIssue(
        'git.base',
        'base commit is not a commit in this repository',
      ),
    );
    return;
  }
  final ProcessResult ancestor = Process.runSync('git', <String>[
    '-C',
    root.path,
    'merge-base',
    '--is-ancestor',
    baseCommit,
    'HEAD',
  ]);
  if (ancestor.exitCode == 1) {
    errors.add(
      const ValidationIssue(
        'git.base',
        'base commit is not an ancestor of HEAD',
      ),
    );
  } else if (ancestor.exitCode != 0) {
    warnings.add(
      const ValidationIssue(
        'git.base',
        'could not verify that the base commit is an ancestor of HEAD',
      ),
    );
  }
}

String _displayReportPath(File report, Directory root) {
  final String? relative = _relativePath(report, root);
  return relative ?? _reportBasename(report);
}

String _reportBasename(File report) {
  final List<String> segments = report.uri.pathSegments;
  if (segments.isEmpty || segments.last.isEmpty) {
    return 'report';
  }
  return segments.last;
}

String? _relativePath(File report, Directory root) {
  final String rootPath = _normalizePath(root.absolute.path);
  final String reportPath = _normalizePath(report.absolute.path);
  if (reportPath == rootPath) {
    return null;
  }
  final String prefix = '$rootPath/';
  if (!reportPath.startsWith(prefix)) {
    return null;
  }
  return reportPath.substring(prefix.length);
}

String _normalizePath(String value) {
  return value.replaceAll(r'\', '/').replaceAll(RegExp(r'/+'), '/');
}

bool _isSafeRelativePath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith('~') ||
      path.contains(r'\') ||
      path.contains(':')) {
    return false;
  }
  final List<String> segments = path.split('/');
  return segments.every(
    (String segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
  }
  return null;
}

Map<String, Object?> _mapOrEmpty(Object? value) {
  return _asMap(value) ?? <String, Object?>{};
}

List<Object?> _listOrEmpty(Object? value) {
  return value is List ? value.cast<Object?>() : <Object?>[];
}

String _stringOrEmpty(Object? value) {
  return value is String ? value : '';
}

Map<String, Object?> _requiredMap(
  Map<String, Object?> map,
  String key,
  String context,
) {
  final Map<String, Object?>? value = _asMap(map[key]);
  if (value == null) {
    throw SchemaException('$context.$key must be an object');
  }
  return value;
}

String _requiredString(Map<String, Object?> map, String key, String context) {
  final Object? value = map[key];
  if (value is! String || value.isEmpty) {
    throw SchemaException('$context.$key must be a non-empty string');
  }
  return value;
}

List<String> _requiredStringList(
  Map<String, Object?> map,
  String key,
  String context,
) {
  final Object? value = map[key];
  if (value is! List ||
      value.isEmpty ||
      value.any((Object? item) => item is! String)) {
    throw SchemaException('$context.$key must be a non-empty string array');
  }
  return value.cast<String>();
}

RegExp _compilePattern(String pattern, String context) {
  try {
    return RegExp(pattern);
  } on FormatException {
    throw SchemaException('$context is not a valid regular expression');
  }
}

bool _matchesType(Object? value, String type) {
  switch (type) {
    case 'object':
      return value is Map;
    case 'array':
      return value is List;
    case 'string':
      return value is String;
    case 'integer':
      return value is int;
    case 'number':
      return value is num;
    case 'boolean':
      return value is bool;
    case 'null':
      return value == null;
    default:
      return false;
  }
}

String _typeName(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is Map) {
    return 'object';
  }
  if (value is List) {
    return 'array';
  }
  if (value is String) {
    return 'string';
  }
  if (value is int) {
    return 'integer';
  }
  if (value is num) {
    return 'number';
  }
  if (value is bool) {
    return 'boolean';
  }
  return value.runtimeType.toString();
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final Object? key in left.keys) {
      if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index++) {
      if (!_deepEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

String _renderValue(Object? value) {
  if (value is String) {
    return '"$value"';
  }
  return '$value';
}

List<ValidationIssue> _dedupe(List<ValidationIssue> issues) {
  final List<ValidationIssue> result = <ValidationIssue>[];
  final Set<String> seen = <String>{};
  for (final ValidationIssue issue in issues) {
    final String key =
        '${issue.code}\u0000${issue.location ?? ''}\u0000'
        '${issue.message}';
    if (seen.add(key)) {
      result.add(issue);
    }
  }
  return result;
}

/// Lowercase hex SHA-256 of [input].
///
/// Vendored FIPS 180-4 implementation so the validator has no package
/// dependency and cannot silently use a different digest implementation.
String sha256Hex(List<int> input) {
  final int paddedLength = ((input.length + 9 + 63) ~/ 64) * 64;
  final Uint8List data = Uint8List(paddedLength);
  data.setRange(0, input.length, input);
  data[input.length] = 0x80;
  int bitLength = input.length * 8;
  for (int index = 0; index < 8; index++) {
    data[paddedLength - 1 - index] = bitLength & 0xFF;
    bitLength >>= 8;
  }

  int h0 = 0x6a09e667;
  int h1 = 0xbb67ae85;
  int h2 = 0x3c6ef372;
  int h3 = 0xa54ff53a;
  int h4 = 0x510e527f;
  int h5 = 0x9b05688c;
  int h6 = 0x1f83d9ab;
  int h7 = 0x5be0cd19;
  final Uint32List schedule = Uint32List(64);

  for (int block = 0; block < paddedLength; block += 64) {
    for (int index = 0; index < 16; index++) {
      final int base = block + index * 4;
      schedule[index] =
          (data[base] << 24) |
          (data[base + 1] << 16) |
          (data[base + 2] << 8) |
          data[base + 3];
    }
    for (int index = 16; index < 64; index++) {
      final int s0 =
          _rotr(schedule[index - 15], 7) ^
          _rotr(schedule[index - 15], 18) ^
          (schedule[index - 15] >> 3);
      final int s1 =
          _rotr(schedule[index - 2], 17) ^
          _rotr(schedule[index - 2], 19) ^
          (schedule[index - 2] >> 10);
      schedule[index] =
          (schedule[index - 16] + s0 + schedule[index - 7] + s1) & 0xFFFFFFFF;
    }

    int a = h0;
    int b = h1;
    int c = h2;
    int d = h3;
    int e = h4;
    int f = h5;
    int g = h6;
    int h = h7;
    for (int index = 0; index < 64; index++) {
      final int sum1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final int choose = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
      final int temp1 =
          (h + sum1 + choose + _sha256K[index] + schedule[index]) & 0xFFFFFFFF;
      final int sum0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final int majority = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = (sum0 + majority) & 0xFFFFFFFF;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xFFFFFFFF;
    }

    h0 = (h0 + a) & 0xFFFFFFFF;
    h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c) & 0xFFFFFFFF;
    h3 = (h3 + d) & 0xFFFFFFFF;
    h4 = (h4 + e) & 0xFFFFFFFF;
    h5 = (h5 + f) & 0xFFFFFFFF;
    h6 = (h6 + g) & 0xFFFFFFFF;
    h7 = (h7 + h) & 0xFFFFFFFF;
  }

  final StringBuffer buffer = StringBuffer();
  for (final int word in <int>[h0, h1, h2, h3, h4, h5, h6, h7]) {
    buffer.write(word.toRadixString(16).padLeft(8, '0'));
  }
  return buffer.toString();
}

int _rotr(int value, int amount) {
  return ((value >> amount) | (value << (32 - amount))) & 0xFFFFFFFF;
}

const List<int> _sha256K = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

String _usage = '''
T032 evidence report validator

Usage:
  dart tools/evaluation/validate_report.dart <report.md> [...]
  dart tools/evaluation/validate_report.dart --schema-check
  dart tools/evaluation/validate_report.dart --json <report.md>

Options:
  --schema PATH              Report schema (default: beside this script).
  --root PATH                Repository root (default: discovered from cwd).
  --json                     Emit machine-readable JSON.
  --schema-check             Validate only the schema, then exit.
  --no-index                 Do not require the report's README index row.
  --no-git                   Do not verify the base commit with git.
  --no-layout                Accept a report outside the evidence root.
  --allow-missing-artifacts  Downgrade absent artifact files to warnings.
  -h, --help                 Show this help.

Exit codes: 0 all reports valid, 1 invalid report, 2 usage/schema error.
''';

int runValidatorCli(List<String> arguments, {bool quiet = false}) {
  String? schemaPath;
  String? rootPath;
  bool json = false;
  bool schemaCheck = false;
  bool checkIndex = true;
  bool verifyGit = true;
  bool checkLayout = true;
  bool allowMissingArtifacts = false;
  final List<String> reports = <String>[];

  try {
    for (int index = 0; index < arguments.length; index++) {
      final String argument = arguments[index];
      switch (argument) {
        case '-h':
        case '--help':
          if (!quiet) {
            stdout.write(_usage);
          }
          return 0;
        case '--json':
          json = true;
        case '--schema-check':
          schemaCheck = true;
        case '--no-index':
          checkIndex = false;
        case '--no-git':
          verifyGit = false;
        case '--no-layout':
          checkLayout = false;
        case '--allow-missing-artifacts':
          allowMissingArtifacts = true;
        case '--schema':
          index++;
          if (index >= arguments.length) {
            throw const _UsageException('--schema requires a path');
          }
          schemaPath = arguments[index];
        case '--root':
          index++;
          if (index >= arguments.length) {
            throw const _UsageException('--root requires a path');
          }
          rootPath = arguments[index];
        default:
          if (argument.startsWith('-')) {
            throw _UsageException('unknown option "$argument"');
          }
          reports.add(argument);
      }
    }

    final Directory root = rootPath != null
        ? Directory(rootPath)
        : _discoverRoot(Directory.current);
    final File schemaFile = schemaPath != null
        ? File(schemaPath)
        : File.fromUri(
            File.fromUri(Platform.script).parent.uri
                .resolve('report_schema.json'),
          );
    final ReportSchema schema = ReportSchema.load(schemaFile);
    if (schemaCheck) {
      if (reports.isNotEmpty) {
        throw const _UsageException(
          '--schema-check does not accept report paths',
        );
      }
      if (json) {
        if (!quiet) {
          stdout.writeln(
            jsonEncode(<String, Object?>{
              'valid': true,
              'schema': schema.schemaId,
              'schemaVersion': schema.document['x-schema-version'] ?? '',
            }),
          );
        }
      } else if (!quiet) {
        stdout.writeln(
          'PASS schema ${schema.schemaId} '
          '(${schema.sectionOrder.length} sections, '
          '${schema.classEnvironment.length} classes)',
        );
      }
      return 0;
    }
    if (reports.isEmpty) {
      throw const _UsageException('at least one report path is required');
    }

    final List<ReportValidation> results = <ReportValidation>[];
    for (final String path in reports) {
      results.add(
        validateReport(
          report: File(path),
          schema: schema,
          root: root,
          checkIndex: checkIndex,
          allowMissingArtifacts: allowMissingArtifacts,
          verifyGit: verifyGit,
          checkLayout: checkLayout,
        ),
      );
    }
    final bool valid = results.every((ReportValidation result) => result.valid);
    if (json) {
      if (!quiet) {
        stdout.writeln(
          jsonEncode(<String, Object?>{
            'valid': valid,
            'schema': schema.schemaId,
            'reports': results
                .map((ReportValidation result) => result.toJson())
                .toList(),
          }),
        );
      }
    } else if (!quiet) {
      for (final ReportValidation result in results) {
        if (result.valid) {
          stdout.writeln('PASS ${result.path}');
        } else {
          stdout.writeln('FAIL ${result.path}');
          for (final ValidationIssue issue in result.errors) {
            stdout.writeln('  - $issue');
          }
        }
        for (final ValidationIssue warning in result.warnings) {
          stdout.writeln('  ! $warning');
        }
      }
      final int failed = results.where((ReportValidation r) => !r.valid).length;
      stdout.writeln(
        '${results.length - failed}/${results.length} report(s) valid',
      );
    }
    return valid ? 0 : 1;
  } on _UsageException catch (error) {
    if (!quiet) {
      stderr.writeln('FAIL: ${error.message}');
      stderr.write(_usage);
    }
    return 2;
  } on SchemaException catch (error) {
    if (!quiet) {
      stderr.writeln('FAIL: report schema: ${error.message}');
    }
    return 2;
  } on FileSystemException catch (error) {
    if (!quiet) {
      stderr.writeln('FAIL: ${error.message}');
    }
    return 2;
  }
}

Directory _discoverRoot(Directory start) {
  Directory current = start.absolute;
  while (true) {
    if (File('${current.path}/pubspec.yaml').existsSync() &&
        Directory('${current.path}/specs').existsSync()) {
      return current;
    }
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      return start.absolute;
    }
    current = parent;
  }
}

void main(List<String> arguments) {
  exitCode = runValidatorCli(arguments);
}
