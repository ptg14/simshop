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
}
