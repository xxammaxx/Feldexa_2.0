// T116 layout-only template editor (FR-101/FR-102; clarification 4).
//
// Owner: `apps/feldexa_app/lib/features/templates/template_editor.dart`.
// Normative sources:
//   * `spec.md` FR-101 (open a stored template and edit its field layout:
//     move, and the layout surface the other edit commands attach to) and
//     FR-102 (layout-only: no field values and no signatures can be entered
//     or stored in a template);
//   * `contracts/editor-interactions.md` — page/viewport conventions;
//   * constitution Principles II, III, V, VI, VIII, and X.
//
// The editor renders the pinned version's page geometry and layout fields on
// a scaled page surface and supports moving a field by drag (FR-101). It has
// no value input, no signature capture, and no suggestion or verification
// surface (FR-102): the only interaction is geometry. Every drag handle is a
// Semantics node whose action target is at least 48x48 logical pixels, and
// the change callbacks report only layout (field id plus new rectangle) —
// the caller persists the change as a new immutable version through the T117
// use case (`templateEditorSaveVersion` action, FR-103).
//
// All user-visible text comes from the German ARB; no German literal appears
// in this file.
//
// Evidence: host-VM widget tests only; evidence class NONE.

import 'package:feldexa_core/feldexa_core.dart' as core;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Stable keys of the editor's surfaces.
const String templateEditorScaffoldKey = 'template-editor-scaffold';
const String templateEditorSaveVersionKey = 'template-editor-save-version';
const String templateEditorFieldKeyPrefix = 'template-editor-field-';

/// One layout change reported by [TemplateEditorView].
final class TemplateLayoutChange {
  /// Creates a content-free layout change for [fieldId].
  const TemplateLayoutChange({required this.fieldId, required this.rect});

  /// The moved layout field.
  final String fieldId;

  /// The field's new rectangle in page coordinates.
  final core.Rect rect;

  @override
  String toString() {
    return 'TemplateLayoutChange(fieldId: $fieldId)';
  }
}

/// A layout field rendered on the page surface.
final class TemplateEditorField {
  /// Creates one layout field entry.
  const TemplateEditorField({
    required this.id,
    required this.label,
    required this.type,
    required this.rect,
  });

  /// Stable field id.
  final String id;

  /// User-visible German label.
  final String label;

  /// Layout field type (signature fields are rendered, never captured).
  final core.FieldType type;

  /// Field rectangle in page coordinates.
  final core.Rect rect;

  /// Returns a copy with [rect] replaced.
  TemplateEditorField withRect(core.Rect rect) =>
      TemplateEditorField(id: id, label: label, type: type, rect: rect);
}

/// One editable template page.
final class TemplateEditorPage {
  /// Creates one page entry.
  const TemplateEditorPage({required this.index, required this.geometry});

  /// Zero-based page index.
  final int index;

  /// Display geometry of the page.
  final core.PageGeometry geometry;
}

/// The layout-only template editor view (FR-101/FR-102).
///
/// [pages] and [fields] describe the pinned version's layout. Dragging a
/// field reports [onLayoutChange]; nothing else is editable. [onSaveVersion]
/// is the caller's "Als neue Version speichern" action (FR-103); it is
/// disabled while [saveVersionEnabled] is false.
class TemplateEditorView extends StatefulWidget {
  /// Creates the editor view.
  const TemplateEditorView({
    required this.pages,
    required this.fields,
    required this.currentPageIndex,
    required this.onLayoutChange,
    required this.onSaveVersion,
    this.saveVersionEnabled = false,
    super.key,
  });

  /// The version's pages, at least one.
  final List<TemplateEditorPage> pages;

  /// The version's layout fields on the current page.
  final List<TemplateEditorField> fields;

  /// The page currently shown.
  final int currentPageIndex;

  /// Called once per completed drag with the moved field's new rectangle.
  final ValueChanged<TemplateLayoutChange> onLayoutChange;

  /// Called when the user confirms a new version.
  final VoidCallback onSaveVersion;

  /// Whether the version-save action is enabled.
  final bool saveVersionEnabled;

  @override
  State<TemplateEditorView> createState() => _TemplateEditorViewState();
}

class _TemplateEditorViewState extends State<TemplateEditorView> {
  static const double _handleMinSize = 48.0;
  static const double _pageWidth = 420.0;

  core.Rect? _dragStartRect;
  Offset? _dragStartGlobal;

  double get _scale => _pageWidth / _displaySize.width;

  core.PageGeometry get _currentGeometry =>
      widget.pages[widget.currentPageIndex].geometry;

  core.Size get _displaySize => _currentGeometry.displaySize;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey<String>(templateEditorScaffoldKey),
      appBar: AppBar(
        title: Text(l10n.templateEditorTitle),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>(templateEditorSaveVersionKey),
            tooltip: l10n.templateEditorSaveVersion,
            onPressed: widget.saveVersionEnabled ? widget.onSaveVersion : null,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(l10n.templateEditorLayoutOnlyNotice),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: _pageWidth,
                    height: _displaySize.height * _scale,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        // Page surface: geometry only, no raster claim.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black26),
                          ),
                          child: const SizedBox.expand(),
                        ),
                        for (final TemplateEditorField field in widget.fields)
                          _layoutField(field, l10n),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layoutField(TemplateEditorField field, AppLocalizations l10n) {
    final core.Rect rect = field.rect;
    return Positioned(
      left: rect.left * _scale,
      top: rect.top * _scale,
      child: GestureDetector(
        key: ValueKey<String>(templateEditorFieldKey(field.id)),
        onPanStart: (DragStartDetails details) {
          _dragStartRect = rect;
          _dragStartGlobal = details.globalPosition;
        },
        onPanUpdate: (DragUpdateDetails details) {
          final Offset? start = _dragStartGlobal;
          final core.Rect? startRect = _dragStartRect;
          if (start == null || startRect == null) {
            return;
          }
          final Offset delta = (details.globalPosition - start) / _scale;
          _dragStartGlobal = details.globalPosition;
          _dragStartRect = core.Rect.fromLTWH(
            startRect.left + delta.dx,
            startRect.top + delta.dy,
            startRect.width,
            startRect.height,
          );
        },
        onPanEnd: (DragEndDetails details) {
          final core.Rect? moved = _dragStartRect;
          _dragStartRect = null;
          _dragStartGlobal = null;
          if (moved != null) {
            widget.onLayoutChange(
              TemplateLayoutChange(fieldId: field.id, rect: moved),
            );
          }
        },
        child: Semantics(
          label: '${field.label}, ${l10n.templateEditorMoveFieldHint}',
          button: false,
          child: SizedBox(
            // Semantics/drag target: never below 48 dp, independent of the
            // exported layout rectangle (FR-101 interaction floor).
            width: rect.width * _scale < _handleMinSize
                ? _handleMinSize
                : rect.width * _scale,
            height: rect.height * _scale < _handleMinSize
                ? _handleMinSize
                : rect.height * _scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: field.type == core.FieldType.signature
                      ? Colors.blueGrey
                      : Colors.blue,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    field.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stable key for one field's drag handle in tests.
String templateEditorFieldKey(String fieldId) =>
    '$templateEditorFieldKeyPrefix$fieldId';
