// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simshop/main.dart';

void main() {
  testWidgets('Home screen has no admin FAB', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const MyApp());
    // Allow any async initialization (e.g., timers, futures) to complete.
    await tester.pumpAndSettle();

    // The admin entry-point was deliberately hidden from casual users —
    // there's no FAB labelled "Quản trị" anymore, and no admin icon on
    // the home screen. Admin now lives behind a hidden 3× long-press
    // on the store name in the footer (see [SiteInfoFooter]). The
    // store name still exists but only on the browser tab
    // (document.title); the test rig doesn't render that, so we don't
    // assert it here.
    expect(find.text('Quản trị'), findsNothing);
    expect(find.byIcon(Icons.admin_panel_settings), findsNothing);
  });
}
