import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/article.dart';
import 'package:simshop/views/article_screen.dart';

void main() {
  testWidgets('ArticleScreen renders title and markdown body', (tester) async {
    const article = Article(
      id: 'a-1',
      title: 'Khuyến mãi tháng 6',
      body: '## Điểm nổi bật\n\nGiảm **30%** cho tất cả sản phẩm.',
    );

    await tester.pumpWidget(
      const MaterialApp(home: ArticleScreen(article: article)),
    );
    await tester.pumpAndSettle();

    // Title shows twice: AppBar + body heading.
    expect(find.text('Khuyến mãi tháng 6'), findsNWidgets(2));
    // Markdown header from the body.
    expect(find.text('Điểm nổi bật'), findsOneWidget);
  });

  testWidgets('ArticleScreen falls back when body is empty', (tester) async {
    const article = Article(id: 'a-2', title: 'Trống', body: '');

    await tester.pumpWidget(
      const MaterialApp(home: ArticleScreen(article: article)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('chưa có nội dung'), findsOneWidget);
  });
}
