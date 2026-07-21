import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/views/admin/admin_product/widgets/options_editor_with_images.dart';

/// Regression for: `RangeError: Value not in range: <len>` thrown from
/// `List.insert` when the admin clicked the "move right" arrow on any
/// option thumbnail that was NOT the very first item.
///
/// Root cause: `_OptionImageRow._reorder` does
///   removeAt(oldIndex); insert(newIndex, moved)
/// so after `removeAt` every subsequent index has already shifted
/// down by one. The right-arrow callback was passing
/// `newIndex = idx + 2` — over-shooting the list whenever the
/// option had >= 2 images. The correct slot is `idx + 1`
/// ("one past where the item used to sit").
///
/// The same bug existed in `ImagePickerGrid`'s right-arrow for the
/// main gallery; we exercise that path here too via
/// `_OptionImageRow` since both widgets now share the corrected
/// `idx + 1` formula.
void main() {
  testWidgets(
      'Option row: clicking "right" on a middle thumb moves it one slot right (no RangeError)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Seed an option whose gallery has 3 distinct URLs so clicking
    // "right" on the MIDDLE one (idx=1) exercises the boundary:
    //   - pre-fix: _reorder(1, 3) → removeAt(1) → insert(3) on a
    //     2-elem list → RangeError("Value not in range: 2").
    //   - post-fix: _reorder(1, 2) → removeAt(1) → insert(2) → fine.
    const urls = [
      'https://example.test/a.jpg',
      'https://example.test/b.jpg',
      'https://example.test/c.jpg',
    ];
    final options = <Option>[
      Option(id: 'o-1', name: 'Màu đỏ', imageUrls: urls),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => OptionsEditorWithImages(
            options: options,
            existingImages: urls,
            newImageBytes: const [],
            onChanged: (opts) => setState(() {
              options
                ..clear()
                ..addAll(opts);
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Find the "right" button on the middle thumb. Each thumb has
    // two stacked arrow buttons; we identify the middle thumb by
    // its underlying URL and the right arrow by its tooltip.
    final middleThumb = find.byWidgetPredicate((w) {
      if (w is! Image) return false;
      return w.image is NetworkImage &&
          (w.image as NetworkImage).url == urls[1];
    });
    expect(middleThumb, findsOneWidget,
        reason: 'middle thumb (b.jpg) must be rendered');

    // The "move right" arrow lives next to the middle thumb. We
    // locate it via the tooltip ('Đưa xuống dưới') — that's the
    // semantic name for the bottom button in the thumb's stack,
    // which is "move right" in our linear reorder scheme.
    final moveRight = find.byTooltip('Đưa xuống dưới');
    expect(moveRight, findsNWidgets(3),
        reason: 'three thumbs → three "move right" buttons');

    // Tap the right button on the MIDDLE thumb. Without the fix
    // this throws `RangeError: Value not in range: 2`.
    final middleRight = moveRight.at(1);
    await tester.tap(middleRight);
    await tester.pumpAndSettle();

    // After the tap, the option's imageUrls must be [a, c, b] —
    // b moved one slot to the right.
    expect(options, hasLength(1));
    expect(options.first.imageUrls, [
      urls[0], // a
      urls[2], // c
      urls[1], // b  ← moved
    ]);
  });

  testWidgets(
      'Option row: clicking "right" on the LAST thumb is a no-op (button is disabled)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const urls = [
      'https://example.test/a.jpg',
      'https://example.test/b.jpg',
    ];
    final options = <Option>[
      Option(id: 'o-1', name: 'Màu đỏ', imageUrls: urls),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => OptionsEditorWithImages(
            options: options,
            existingImages: urls,
            newImageBytes: const [],
            onChanged: (opts) => setState(() {
              options
                ..clear()
                ..addAll(opts);
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final lastRight = find.byTooltip('Đưa xuống dưới').at(1);
    await tester.tap(lastRight, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Order unchanged — last thumb's "right" is disabled.
    expect(options.first.imageUrls, urls);
  });
}