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
/// The widget owns a [TextEditingController] so callers don't have to
/// track the controller themselves; they read [controller] when
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
  final int minLines;
  final int maxLines;

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
    final body = useSplit ? _buildSplit(context) : _buildStacked(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          height: useSplit ? 360 : null,
          child: body,
        ),
      ],
    );
  }

  Widget _buildSplit(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildSourceField(boxed: false)),
        const VerticalDivider(width: 1),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SingleChildScrollView(child: _buildPreview()),
          ),
        ),
      ],
    );
  }

  Widget _buildStacked(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSourceField(boxed: true),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(child: _buildPreview()),
        ),
      ],
    );
  }

  Widget _buildSourceField({required bool boxed}) {
    final scheme = Theme.of(context).colorScheme;
    final field = TextField(
      controller: _controller,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: '## Tiêu đề phụ\n\nViết **in đậm**, _in nghiêng_...',
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

  Widget _buildPreview() {
    final data = _controller.text.isEmpty ? '_(Xem trước nội dung)_' : _controller.text;
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
    );
  }
}
