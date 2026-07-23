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

  Future<bool> readIsTablet(WidgetTester tester, double width) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(builder: (context) {
          // ignore: unused_local_variable
          final _ = context.isTabletOrUp;
          return const SizedBox.shrink();
        }),
      ),
    ));
    return tester.element(find.byType(SizedBox)).isTabletOrUp;
  }

  testWidgets('productDetailImageHeight: mobile=320, tablet=480, desktop=600',
      (tester) async {
    expect(await readHeight(tester, 390), 320);
    expect(await readHeight(tester, 800), 480);
    expect(await readHeight(tester, 1280), 600);
  });

  testWidgets('isTabletOrUp is false at <600dp, true at >=600dp',
      (tester) async {
    expect(await readIsTablet(tester, 599), isFalse);
    expect(await readIsTablet(tester, 600), isTrue);
    expect(await readIsTablet(tester, 1280), isTrue);
  });

  // New breakpoint for the iPad/PC layout split:
  //   <1024dp  → mobile / iPad portrait (single column)
  //   ≥1024dp  → iPad landscape / PC / laptop (2-column + thumbs
  //             below the row)
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

  test('Breakpoints.productDetailTwoCol is 1024 dp (legacy fallback)', () {
    // The constant is kept for callers that want a static fallback;
    // the getter itself now reads MediaQuery.orientation.
    expect(Breakpoints.productDetailTwoCol, 1024);
  });

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
    // PC layout. Note that 932×430 (iPhone landscape) is the new
    // case this rule adds: width is only 932 dp (under the
    // previous 1024 dp threshold) but the device is in landscape
    // → 2-col.
    expect(
        await readIsProductDetailTwoCol(
          tester,
          width: 932,
          height: 430,
        ),
        isTrue,
        reason: 'iPhone 14 Pro Max landscape — the NEW rule: 2-col even '
            'though width < 1024 dp');
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
