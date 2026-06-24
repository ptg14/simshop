import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/widgets/markdown_split_editor.dart';

void main() {
  testWidgets('MarkdownSplitEditor renders preview that updates on type',
      (tester) async {
    final key = GlobalKey<MarkdownSplitEditorState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200, // wide so split layout is used
          child: MarkdownSplitEditor(
            key: key,
            initialValue: '',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Set text via the public helper and rebuild.
    key.currentState?.setText('**bold**');
    await tester.pump();

    // The Markdown renderer turns **bold** into the word "bold" wrapped
    // in a <strong>. The text "bold" appears in the preview pane.
    expect(find.text('bold'), findsWidgets);
  });
}
