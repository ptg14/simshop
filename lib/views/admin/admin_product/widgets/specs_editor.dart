import 'package:flutter/material.dart';

import '../../../../utils/responsive.dart';

/// Editor for the product's `specs` field (thông số kỹ thuật).
///
/// Each spec is rendered as a row with a TextField + delete button,
/// followed by a single trailing "Thêm dòng" button. Mirrors the
/// shape of OptionsEditorWithImages so Add and Edit product dialogs
/// share one look-and-feel for dynamic-list content fields.
///
/// Parent state (`specs`) is the source of truth: we sync our local
/// TextEditingController pool to it whenever the incoming list length
/// changes (add/delete). Mid-list edits flow directly through each
/// controller's `onChanged` so cursor state, IME selection, and
/// composition ranges survive keystrokes.
class SpecsEditor extends StatefulWidget {
  const SpecsEditor({
    super.key,
    required this.specs,
    required this.onChanged,
  });

  final List<String> specs;
  final ValueChanged<List<String>> onChanged;

  @override
  State<SpecsEditor> createState() => _SpecsEditorState();
}

class _SpecsEditorState extends State<SpecsEditor> {
  // One controller per spec row. We mutate this list in lock-step
  // with [widget.specs] so adding/removing rows is cheap and the
  // TextField for each row keeps its cursor state across rebuilds.
  late final List<TextEditingController> _controllers;
  // One focus node per row, paired by index. We use `hasFocus` to
  // decide whether an external value change should clobber the
  // controller's text (only safe when the row isn't actively being
  // edited).
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = widget.specs.map(_makeController).toList();
    _focusNodes = List<FocusNode>.generate(widget.specs.length, (_) => FocusNode());
  }

  TextEditingController _makeController(String text) {
    final c = TextEditingController(text: text);
    // Selection collapsed to the end so a freshly-pushed empty row
    // is ready to type into without an extra tap. The controller's
    // own selection setter is safe here because nothing is mounted
    // yet.
    c.selection = TextSelection.collapsed(offset: text.length);
    return c;
  }

  @override
  void didUpdateWidget(covariant SpecsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  /// Reconcile our local controller pool with [widget.specs].
  ///
  /// - If a row was added, push a new controller + focus node whose
  ///   text matches the new spec entry (this happens on "Thêm dòng").
  /// - If a row was removed, drop the corresponding controller + node.
  /// - If a row's text differs from its controller (e.g. parent
  ///   reset state externally), update the controller without
  ///   clobbering an in-progress edit. We skip rows that currently
  ///   have focus so the user's cursor and IME state survive.
  void _syncControllers() {
    final specs = widget.specs;
    if (_controllers.length != specs.length) {
      // Length changed — rebuild both pools to keep the indices aligned.
      for (final c in _controllers) {
        c.dispose();
      }
      for (final n in _focusNodes) {
        n.dispose();
      }
      _controllers
        ..clear()
        ..addAll(specs.map(_makeController));
      _focusNodes
        ..clear()
        ..addAll(List<FocusNode>.generate(specs.length, (_) => FocusNode()));
      return;
    }
    // Length matched: refresh text only where the parent value
    // diverges from the controller. Skip rows the user is actively
    // editing — they're the source of truth.
    for (var i = 0; i < specs.length; i++) {
      final controller = _controllers[i];
      final node = _focusNodes[i];
      if (!node.hasFocus && controller.text != specs[i]) {
        controller.value = TextEditingValue(
          text: specs[i],
          selection: TextSelection.collapsed(offset: specs[i].length),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _emitChange() {
    // Snapshot the controllers in order. The parent re-renders us
    // with this list as `widget.specs`, and _syncControllers keeps
    // the pool aligned.
    widget.onChanged(_controllers.map((c) => c.text).toList());
  }

  void _handleRowChanged(int i, String value) {
    final updated = List<String>.from(widget.specs);
    updated[i] = value;
    widget.onChanged(updated);
  }

  void _handleDelete(int i) {
    final updated = List<String>.from(widget.specs)..removeAt(i);
    widget.onChanged(updated);
  }

  void _handleAdd() {
    final updated = List<String>.from(widget.specs)..add('');
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.formDialogWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thông số kỹ thuật',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < widget.specs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controllers[i],
                        focusNode: _focusNodes[i],
                        decoration: const InputDecoration(
                          isDense: true,
                        ),
                        onChanged: (v) => _handleRowChanged(i, v),
                        // Re-emit the latest text when focus leaves
                        // the field so a copy/paste that bypassed
                        // onChanged (e.g. paste via right-click
                        // menu) still flows up. Cheap and idempotent.
                        onEditingComplete: _emitChange,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      tooltip: 'Xoá dòng',
                      onPressed: () => _handleDelete(i),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _handleAdd,
              icon: const Icon(Icons.add),
              label: const Text('Thêm dòng'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
}