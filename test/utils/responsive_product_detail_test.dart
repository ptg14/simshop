import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/utils/responsive.dart';

void main() {
  Future<double> readHeight(WidgetTester tester, double width) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(builder: (context) {
          // ignore: unused_local_variable
          final _ = context.productDetailImageHeight;
          return const SizedBox.shrink();
        }),
      ),
    ));
    return tester.element(find.byType(SizedBox)).productDetailImageHeight;
  }

  testWidgets('productDetailImageHeight: mobile=320, tablet=480, desktop=600',
      (tester) async {
    expect(await readHeight(tester, 390), 320);
    expect(await readHeight(tester, 800), 480);
    expect(await readHeight(tester, 1280), 600);
  });

  // Orientation-based rule for the product-detail layout:
  //   portrait  (height >= width) → mobile / iPad portrait (single column)
  //   landscape (width > height)  → iPad landscape / PC / laptop
  //                                  (2-column + thumbs below the row)
  Future<bool> readIsProductDetailTwoCol(
    WidgetTester tester, {
    required double width,
    required double height,
  }) async {
    // Orientation is derived from size by Flutter (width > height
    // → landscape). The expected orientation is implied by the
    // size the caller passes; we don't try to override it
    // separately because MediaQueryData doesn't expose
    // orientation as a constructor field.
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: Builder(builder: (context) {
          // ignore: unused_local_variable
          final _ = context.isProductDetailTwoCol;
          return const SizedBox.shrink();
        }),
      ),
    ));
    return tester.element(find.byType(SizedBox)).isProductDetailTwoCol;
  }

  testWidgets(
      'isProductDetailTwoCol: true in landscape (phone landscape / '
      'iPad landscape / PC), false in portrait (phone portrait / '
      'iPad portrait) — orientation-based rule',
      (tester) async {
    // PORTRAIT cases (height >= width → MediaQuery.orientation
    // == portrait) — must stay single-column.
    expect(
        await readIsProductDetailTwoCol(
          tester,
          width: 430,
          height: 932,
        ),
        isFalse,
        reason: 'iPhone 14 Pro Max portrait — mobile layout');
    expect(
        await readIsProductDetailTwoCol(
          tester,
          width: 768,
          height: 1024,
        ),
        isFalse,
        reason: 'iPad portrait — must stay mobile-style');
    expect(
        await readIsProductDetailTwoCol(
          tester,
          width: 1280,
          height: 1500, // > 1280 → portrait
        ),
        isFalse,
        reason: 'tall layout in portrait must stay single-column even '
            'when width is huge');

    // LANDSCAPE cases (width > height → landscape) — must use 2-col
    // PC layout. Note that 932×430 (iPhone landscape) is the case
    // this rule covers: width is only 932 dp (under the previous
    // 1024 dp threshold) but the device is in landscape → 2-col.
    expect(
        await readIsProductDetailTwoCol(
          tester,
          width: 932,
          height: 430,
        ),
        isTrue,
        reason: 'iPhone 14 Pro Max landscape — 2-col even though '
            'width < 1024 dp');
    expect(
        await readIsProductDetailTwoCol(
          tester,
          width: 1024,
          height: 768,
        ),
        isTrue,
        reason: 'iPad landscape — 2-col');
    expect(
        await readIsProductDetailTwoCol(
          tester,
          width: 1280,
          height: 800,
        ),
        isTrue,
        reason: 'PC / laptop — 2-col');
  });
}
