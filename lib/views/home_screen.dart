import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../viewmodels/articles_viewmodel.dart';
import '../viewmodels/home_viewmodel.dart';
import '../widgets/category_selector.dart';
import '../widgets/image_carousel.dart';
import '../widgets/product_card.dart';
import '../widgets/site_info_footer.dart';
import 'article_screen.dart';
import 'product_detail_screen.dart';

/// Home screen displaying products and promotions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().initialize();
    });
  }

  void _navigateToProductDetail(Product product) {
    Navigator.of(context).push(
      fadeSlideRoute(ProductDetailScreen(product: product)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The AppBar has been removed by request. The browser tab title
    // is managed by [BrowserTitleManager] at the [MyApp] level — that
    // way the title survives navigation push/pop instead of being
    // reset to [MaterialApp.title] every time a new screen comes
    // to the top.
    //
    // Admin entry-point is intentionally not surfaced here — it lives
    // on a hidden 7× tap on the store banner in the site info footer
    // (see [SiteInfoFooter]). Casual users have no UI hint that admin
    // exists; they must already know the secret handshake to open the
    // auth gate.
    return Scaffold(
        body: Consumer<HomeViewModel>(
          builder: (context, viewModel, _) {
            if (viewModel.isLoading && viewModel.products.isEmpty) {
              return Center(
                child: CircularProgressIndicator(color: scheme.primary),
              );
            }
            if (viewModel.error != null && viewModel.products.isEmpty) {
              return _buildError(context, viewModel);
            }
            return RefreshIndicator(
              color: scheme.primary,
              onRefresh: viewModel.initialize,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: context.maxContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top breathing room. The previous AppBar used
                        // to give content visual separation from the
                        // status bar; without it the carousel butts up
                        // against the top edge. A small responsive
                        // spacer restores that gap (slightly larger on
                        // tablet/desktop where the carousel is taller
                        // and the screen has more vertical real estate).
                        SizedBox(height: context.responsive<double>(
                          mobile: 12,
                          tablet: 20,
                          desktop: 24,
                        )),
                        // Promotional banner carousel. Pulled from the
                        // backend via ArticlesViewModel; each slide carries
                        // an articleId which the tap handler opens via
                        // ArticleScreen (slice 4 wires the fetch-by-id).
                        Consumer<ArticlesViewModel>(
                          builder: (context, articlesVm, _) {
                            final banners = articlesVm.banners;
                            if (banners.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return ImageCarousel(
                              imageUrls: banners
                                  .map((b) => b.imageUrl)
                                  .toList(growable: false),
                              height: context.carouselHeight,
                              onTap: (index) {
                                final articleId = banners[index].articleId;
                                if (articleId == null || articleId.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Không có bài viết'),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.of(context).push(
                                  openArticleIdRoute(articleId),
                                );
                              },
                            );
                          },
                        ),
                        // Category selector (Large + sub rows).
                        CategorySelector(
                          largeCategories: viewModel.largeCategories,
                          selectedLarge: viewModel.selectedLarge,
                          onLargeSelected: viewModel.selectLarge,
                          subCategories: viewModel.visibleSubCategories,
                          selectedSub: viewModel.selectedCategory,
                          onSubSelected: viewModel.selectCategory,
                        ),
                        // Product grid or empty state
                        if (viewModel.products.isEmpty)
                          _buildEmpty(context, viewModel)
                        else
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: context.horizontalPadding,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final crossAxisCount = context.gridColumns;
                                final spacing = context.gridSpacing;
// Card layout: a fixed-`mainAxisExtent` [GridView] sized so
                                // each cell is exactly the height of
                                // the worst-case product card (image +
                                // name + options + categories + price
                                // + button) on the current breakpoint.
                                // That way every card sits flush at the
                                // top and bottom of its cell — no
                                // blank strip under the "Xem chi tiết"
                                // button, and no cards offset relative
                                // to each other.
                                //
                                // `mainAxisExtent` (height in dp) is
                                // used instead of `childAspectRatio`
                                // (width/height) because the cell width
                                // depends on the viewport, which makes
                                // aspect ratios fragile across
                                // orientation changes (phone landscape,
                                // iPad portrait/landscape). [ProductCard]
                                // uses placeholder [SizedBox]es when
                                // options/categories are missing so the
                                // price + button baseline still match
                                // cards with all fields.
                                final cellHeight =
                                    context.productCardHeight;

                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.only(
                                    top: context.gridSpacing,
                                    bottom: 16,
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisExtent: cellHeight,
                                    crossAxisSpacing: spacing,
                                    mainAxisSpacing: spacing,
                                  ),
                                  itemCount: viewModel.products.length,
                                  itemBuilder: (context, index) {
                                    final product = viewModel.products[index];
                                    return ProductCard(
                                      product: product,
                                      onTap: () => _navigateToProductDetail(
                                        product,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        const SiteInfoFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
  }

  Widget _buildEmpty(BuildContext context, HomeViewModel viewModel) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 80, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Không tìm thấy sản phẩm nào',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hãy thử chọn danh mục khác',
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, HomeViewModel viewModel) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              'Không thể tải sản phẩm',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              viewModel.error!,
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: viewModel.initialize,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}
