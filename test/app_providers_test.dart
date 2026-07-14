import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/main.dart';
import 'package:simshop/services/article_service.dart';
import 'package:simshop/services/product_service.dart';

/// Pumping [MyApp] should expose both [IProductService] and
/// [IArticleService] via Provider so widgets that `context.read` them
/// (e.g. the banner dialog's image uploader and the article screen)
/// don't throw ProviderNotFoundException.
///
/// Bug history: 78f3492 added the ArticlesViewModel provider but
/// never registered the underlying services, so the banner dialog
/// crashed with `Could not find the correct Provider<IProductService>`
/// when the admin taps Lưu after picking an image.
void main() {
  testWidgets('MyApp exposes IProductService and IArticleService providers',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // `context.read` throws ProviderNotFoundException synchronously
    // if no matching ancestor Provider exists, so this is a
    // direct reproduction of the original bug.
    final element = tester.element(find.byType(MaterialApp).first);
    expect(() => Provider.of<IProductService>(element, listen: false),
        returnsNormally,
        reason: 'IProductService must be registered in MyApp MultiProvider');
    expect(() => Provider.of<IArticleService>(element, listen: false),
        returnsNormally,
        reason: 'IArticleService must be registered in MyApp MultiProvider');

    // And the values should be the real service implementations,
    // not null — proving the providers actually resolved.
    final productService =
        Provider.of<IProductService>(element, listen: false);
    final articleService =
        Provider.of<IArticleService>(element, listen: false);
    expect(productService, isA<RealProductService>());
    expect(articleService, isA<RealArticleService>());
  });
}
