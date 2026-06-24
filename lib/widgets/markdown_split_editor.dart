import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../utils/responsive.dart';

/// Split-pane Markdown editor.
///
/// On wide viewports (admin uses NavigationRail), the editor is laid
/// out as `Row([TextField, Divider, MarkdownBody])` so the admin can
/// see the rendered preview alongside the source. On mobile widths the
/// panes stack vertically to keep both readable.
///
/// **Sizing**: both panes share a fixed 320px height (source + preview)
/// so the dialog they sit in doesn't grow vertically with the
/// Markdown length. The source `TextField` uses `expands: true` to
/// fill its pane; the preview pane scrolls internally. The
/// [minLines] / [maxLines] constructor params are kept for backwards
/// compatibility but no longer affect rendered height.
///
/// The widget owns a [TextEditingController] so callers don't have to
/// track the controller themselves; they read `controller.text` when
/// submitting the form.
class MarkdownSplitEditor extends StatefulWidget {
  const MarkdownSplitEditor({
    super.key,
    required this.initialValue,
    this.labelText = 'Nội dung (Markdown)',
    this.minLines = 8,
    this.maxLines = 16,
  });

  final String initialValue;
  final String labelText;

  /// Kept for backwards compatibility; with the fixed 320px height
  /// these no longer affect rendered height (the field uses
  /// `expands: true`).
  final int minLines;
  final int maxLines;

  /// Fixed editor height for both panes. Shared between split and
  /// stacked layouts so source and preview panes stay equal and the
  /// surrounding dialog doesn't grow with Markdown length.
  static const double paneHeight = 320;

  @override
  State<MarkdownSplitEditor> createState() => MarkdownSplitEditorState();
}

class MarkdownSplitEditorState extends State<MarkdownSplitEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    // Rebuild the preview pane on every keystroke.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Public accessor for callers that need to read the current text
  /// when submitting the form.
  String get text => _controller.text;

  /// Replace the editor contents. Used by tests that need to mutate
  /// the field without going through keystrokes.
  void setText(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useSplit = context.useNavigationRail;
    final body = useSplit ? _buildSplit() : _buildStacked();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            widget.labelText,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        SizedBox(
          height: MarkdownSplitEditor.paneHeight,
          child: body,
        ),
      ],
    );
  }

  Widget _buildSplit() => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildSourceField(boxed: false)),
          const VerticalDivider(width: 1),
          Expanded(child: _buildPreviewPane(boxed: false)),
        ],
      );

  Widget _buildStacked() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildSourceField(boxed: true)),
          const SizedBox(height: 8),
          Expanded(child: _buildPreviewPane(boxed: true)),
        ],
      );

  Widget _buildSourceField({required bool boxed}) {
    final scheme = Theme.of(context).colorScheme;
    final field = TextField(
      controller: _controller,
      // Fill the parent pane so source and preview panes share the
      // 320px height equally.
      expands: true,
      maxLines: null,
      minLines: null,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.all(12),
        isDense: true,
      ),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
      ),
    );
    if (!boxed) return field;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: field,
    );
  }

  Widget _buildPreviewPane({required bool boxed}) {
    final scheme = Theme.of(context).colorScheme;
    final scroll = SingleChildScrollView(child: _buildPreview());
    if (!boxed) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: scheme.surfaceContainerHighest,
        child: scroll,
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: scroll,
    );
  }

  Widget _buildPreview() {
    final data = _controller.text.isEmpty ? '_(Xem trước nội dung)_' : _controller.text;
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
    );
  }
}