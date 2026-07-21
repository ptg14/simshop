import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/views/admin/admin_product/widgets/options_editor_with_images.dart';

/// User reported: in the Add/Edit product dialog, the option row's
/// "Tên option" label and the image-picker area were vertically
/// misaligned — the image picker sat lower than the field label
/// instead of starting at the same y.
///
/// Layout structure (current code):
///   Row(crossAxisAlignment: center)
///     Expanded(flex:3, TextFormField labelText='Tên option')
///     IconButton(delete)
///
/// Image picker below in its own column (Wrap of thumbs). The
/// picker column sits in its own line so the picker is never
/// clipped by Row's `crossAxisAlignment: center`.
///
/// The original fix was IntrinsicHeight on the parent + a fixed
/// "Ảnh" label that always rendered. The new layout removes that
/// redundant label (the column header now reads "Thêm ảnh cho
/// option:" only when there's something to add). This test pins
/// the new behaviour: the "Tên option" floating label is
/// positioned next to the delete IconButton (same row, same y)
/// and the image strip below it is unaffected.
void main() {
  testWidgets(
      'Option row: Tên option label aligns with delete IconButton (same row)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final options = <Option>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => OptionsEditorWithImages(
            options: options,
            existingImages: const [],
            newImageBytes: const [],
            onChanged: (opts) => setState(() => options
              ..clear()
              ..addAll(opts)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap "Thêm option" to create the empty option the user sees.
    await tester.tap(find.text('Thêm option'));
    await tester.pumpAndSettle();

    // The "Tên option" field exists.
    expect(find.text('Tên option'), findsOneWidget);

    // The delete IconButton is in the same row as the field — its
    // y-coord should match the field's top within a small
    // tolerance (TextFormField's floating label baseline lines up
    // with the IconButton hit area).
    final deleteButton = find.byIcon(Icons.delete);
    expect(deleteButton, findsOneWidget);
    final optionFieldTop = tester.getTopLeft(find.text('Tên option')).dy;
    final deleteTop = tester.getTopLeft(deleteButton).dy;
    expect(
      (optionFieldTop - deleteTop).abs(),
      lessThanOrEqualTo(8),
      reason:
          'Tên option label (y=$optionFieldTop) and delete button '
          '(y=$deleteTop) must share the same row, not be stacked',
    );
  });
}