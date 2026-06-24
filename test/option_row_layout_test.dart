import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/views/admin/admin_product/widgets/options_editor_with_images.dart';

/// User reported: in the Add/Edit product dialog, the option row's
/// "Tên option" label and the "Ảnh" label are vertically
/// misaligned — "ảnh" sits below "option" instead of next to it.
///
/// Layout structure (current code):
///   IntrinsicHeight
///     Row(crossAxisAlignment: start)
///       Expanded(flex:3, TextFormField labelText='Tên option')
///       Expanded(flex:2, Column [
///           Text('Ảnh', fontSize:12),
///           SizedBox(h:6),
///           _OptionImageRow(...),
///         ])
///       IconButton(delete)
///
/// When there are no images, `_OptionImageRow` returns a `TextButton`
/// ("Không") that is much shorter than the TextFormField. The
/// IntrinsicHeight row sizes to the tallest child (the
/// TextFormField), so the Column on the right takes that full
/// height. With `crossAxisAlignment: start` the children top-align,
/// so the "Ảnh" Text and the "Tên option" floating label SHOULD
/// start at the same y.
///
/// The reported bug is that they don't. The test below pins the
/// expectation that they do.
void main() {
  testWidgets(
      'Option row: Ảnh label sits at the same y as the Tên option floating label',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Empty initialValue so the TextFormField label sits *inside*
// the field as placeholder text (the user-reported state for new
// options created via "Thêm option" which sets name='Option').
// With IntrinsicHeight + CrossAxisAlignment.start, the empty
// field is taller than the "Ảnh" + "Không" column on the right,
// and the column top-aligns — leaving "ảnh" sitting at the very
// top while the option placeholder sits centered below it. That's
// the misaligned state in the user's screenshot.
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

    // The two labels exist.
    expect(find.text('Tên option'), findsOneWidget);
    expect(find.text('Ảnh'), findsOneWidget);

    // Their top y-coords must match (within a small tolerance for
    // font baseline differences).
    final optionLabelTop = tester.getTopLeft(find.text('Tên option')).dy;
    final anhLabelTop = tester.getTopLeft(find.text('Ảnh')).dy;
    // ignore: avoid_print
    print('DEBUG optionLabelTop=$optionLabelTop anhLabelTop=$anhLabelTop');
    expect(
      (optionLabelTop - anhLabelTop).abs(),
      lessThanOrEqualTo(4),
      reason:
          'Tên option label (y=$optionLabelTop) and Ảnh label '
          '(y=$anhLabelTop) must be aligned, not stacked',
    );
  });
}