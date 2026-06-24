import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/widgets/markdown_split_editor.dart';

/// Forces the test view to a given logical size and restores it
/// afterwards. `useNavigationRail` reads `MediaQuery.size`, so the
/// default 800x600 test surface always picks split mode — we need
/// to opt into stacked mode explicitly.
Future<void> _setScreenSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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

  testWidgets('Split panes share the fixed 320px height', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200, // split layout (useNavigationRail = true)
          child: MarkdownSplitEditor(initialValue: '# Hi'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final textField = tester.getSize(find.byType(TextField));
    // Source pane = 320px tall; the TextField fills it via expands:true.
    // ±4px tolerance for borders.
    expect(textField.height, inInclusiveRange(316, 324));
  });

  testWidgets('Stacked panes share the fixed 320px height', (tester) async {
    await _setScreenSize(tester, const Size(400, 800));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: MarkdownSplitEditor(initialValue: '# Hi'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Stacked = (320 - 8 gap) / 2 = 156 per pane, minus 8+12 padding
    // around the source field = ~138. Allow ±10px for theme diffs.
    final textField = tester.getSize(find.byType(TextField));
    expect(textField.height, inInclusiveRange(128, 160));
    expect(textField.height, greaterThan(100));
  });

  testWidgets('Source TextField has no placeholder hint text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          child: MarkdownSplitEditor(initialValue: ''),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The old hint was '## Tiêu đề phụ\n\nViết **in đậm**, _in nghiêng_...'
    // — should no longer appear as the TextField's hint or anywhere
    // in the source pane.
    expect(find.textContaining('Tiêu đề phụ'), findsNothing);
    expect(find.textContaining('in đậm'), findsNothing);
  });
}
