import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/banner.dart';
import '../models/product.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../viewmodels/articles_viewmodel.dart';
import '../viewmodels/home_viewmodel.dart';
import '../widgets/category_selector.dart';
import '../widgets/home_skeleton.dart';
import '../widgets/image_carousel.dart';
import '../widgets/product_card.dart';
import '../widgets/site_info_footer.dart';
import 'article_screen.dart';
import 'product_detail_screen.dart';

/// Home screen displaying products and promotions.
///
/// Layout & data flow after the performance pass (slice 6):
///
///   • Frame 1: [HomeSkeleton] paints the layout silhouette using
///     [ShimmerBox]. No [Consumer]/[Selector] is mounted yet — the
///     page reads zero state on its first build, so the spinner that
///     used to block the first paint is gone.
///   • `initState` schedules a post-frame `loadCriticalData()` and
///     then an aux `loadAuxData()` one frame later. `loadCriticalData`
///     only fires `getAllProducts()` + `getLargeCategories()` so the
///     user sees real chips and product cards as soon as possible.
///   • [Selector]s wrap each section so only the widget that changed
///     rebuilds — `HomeViewModel.notifyListeners()` no longer rebuilds
///     the carousel, footer, or unrelated chip rows.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Schedule the two data waves one frame apart. Frame N+1 fires
    // the critical GETs (products + Large categories); frame N+2
    // fires the aux GETs (articles/banners, site info, sub-categories).
    // We split them because the home screen can render a *useful*
    // first paint with just products + Large chips — the user can
    // already scroll the grid and pick the default "Tất cả" filter.
    // Loading banners + sub-categories + site info only adds polish,
    // so they sit behind a one-frame delay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Reading HomeViewModel here is safe — the Provider is
      // registered at the root with `lazy: true`, so this is the
      // moment that constructs it. We immediately kick off the
      // critical wave so the very first build of HomeScreen — which
      // happened *before* this post-frame callback — already painted
      // the skeleton instead of waiting for the network.
      final vm = context.read<HomeViewModel>();
      vm.loadCriticalData();

      // Defer aux loads one more frame so the critical HTTP is in
      // flight before TCP slow-start is split across more
      // connections. Cheap to add (one addPostFrameCallback) but
      // reduces the chance of stalling on the second DNS lookup if
      // the device has just woke its radio.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        vm.loadAuxData();
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _navigateToProductDetail(Product product) {
    Navigator.of(context).push(
      fadeSlideRoute(ProductDetailScreen(product: product)),
    );
  }

  @override
  // Block body on purpose — the build branch decides between the
  // skeleton path and the loaded path with a `Consumer`, neither of
  // which collapses into a single expression without obscuring the
  // explainer comments above each branch.
  // ignore: prefer_expression_function_bodies
  Widget build(BuildContext context) {
    return Scaffold(
      // Render the skeleton when [HomeViewModel] hasn't been touched
      // yet, OR when it has but no products have landed. Skipping
      // the [Consumer] branch on the lazy path means the skeleton
      // is rendered without ever reading from a ChangeNotifier —
      // which keeps the first paint off of any provider listener.
      body: Consumer<HomeViewModel>(
        builder: (context, viewModel, _) {
          // Show skeleton only while the raw product list hasn't
          // been populated yet. We must NOT use `products.isEmpty`
          // here — that getter returns the *filtered* list, so
          // picking a Large/sub with zero matching products would
          // flash the skeleton back on screen. `hasLoadedProducts`
          // is the correct "loading finished at least once" signal.
          if (!viewModel.hasLoadedProducts) {
            return _buildFirstPaint(viewModel);
          }
          return _buildLoaded(viewModel);
        },
      ),
    );
  }

  /// Build the body when no products have arrived yet. We still drive
  /// the existing error / skeleton branching here so the skeleton →
  /// grid transition is one rebuild, not two.
  Widget _buildFirstPaint(HomeViewModel viewModel) {
    final scheme = Theme.of(context).colorScheme;
    if (viewModel.error != null) {
      return _buildError(viewModel);
    }
    // Skeleton + RefreshIndicator so pull-to-refresh works from the
    // very first frame. We hand the skeleton the same gesture arena
    // the real grid uses.
    return RefreshIndicator(
      color: scheme.primary,
      onRefresh: viewModel.initialize,
      child: const HomeSkeleton(),
    );
  }

  /// Build the body once products are present. Each section is wrapped
  /// in a [Selector] so updates to, say, banners don't rebuild the
  /// product grid.
  // Block body on purpose — `_buildLoaded` is a multi-step layout
  // (RefreshIndicator → SingleChildScrollView → Center → Container
  // → Column) and an expression body would force an unreadable
  // nested-chain literal.
  // ignore: prefer_expression_function_bodies
  Widget _buildLoaded(HomeViewModel viewModel) {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
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
                SizedBox(height: context.responsive<double>(
                  mobile: 12,
                  tablet: 20,
                  desktop: 24,
                )),
                // Banner carousel — Selector on `ArticlesViewModel`
                // so it rebuilds only when the banners list changes.
                Selector<ArticlesViewModel, List<BannerSlide>>(
                  selector: (_, vm) => vm.banners,
                  builder: (context, banners, _) {
                    // Filter out banners without an imageUrl so the
                    // carousel never gets a null URL passed in.
                    final urls = <String>[
                      for (final b in banners)
                        if (b.imageUrl.isNotEmpty) b.imageUrl,
                    ];
                    if (urls.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return ImageCarousel(
                      imageUrls: urls,
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
                // Category selector — Selector on the four fields
                // the widget actually consumes. Each rebuild is
                // narrowly targeted so a Large toggle doesn't also
                // rebuild the grid below.
                Selector<HomeViewModel, ({List<String> large, String sel, List<String> subs, Set<String> selectedSubs})>(
                  selector: (_, vm) => (
                    large: vm.largeCategories,
                    sel: vm.selectedLarge,
                    subs: vm.visibleSubCategories,
                    selectedSubs: vm.selectedSubs,
                  ),
                  // Block body on purpose — the builder returns a
                  // `CategorySelector` with named arguments sourced
                  // from the snapshot record. An expression body
                  // would either need a builder factory or a deeply
                  // nested constructor call.
                  // ignore: prefer_expression_function_bodies
                  builder: (context, snapshot, _) {
                    return CategorySelector(
                      largeCategories: snapshot.large,
                      selectedLarge: snapshot.sel,
                      onLargeSelected: viewModel.selectLarge,
                      subCategories: snapshot.subs,
                      selectedSubs: snapshot.selectedSubs,
                      onSubToggled: viewModel.toggleSub,
                    );
                  },
                ),
                // Product grid — Selector on `_filteredProducts`
                // only. A category change rebuilds this Selector
                // *and* the chip Selector above, but the
                // footer / carousel below stay untouched.
                Selector<HomeViewModel, List<Product>>(
                  selector: (_, vm) => vm.products,
                  builder: (context, products, _) {
                    if (products.isEmpty) {
                      return _buildEmpty(viewModel);
                    }
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.horizontalPadding,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount = context.gridColumns;
                          final spacing = context.gridSpacing;
                          final cellHeight = context.productCardHeight;
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
                            itemCount: products.length,
                            itemBuilder: (context, index) {
                              final product = products[index];
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
                    );
                  },
                ),
                // Footer — kept as a Consumer because it owns its
                // own gatekeeper and only listens to a single VM,
                // so its rebuild scope is already tiny.
                const SiteInfoFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(HomeViewModel viewModel) {
    final scheme = Theme.of(context).colorScheme;
    // Empty state shown when the active Large/sub filter happens
    // to match zero products. This is rendered inside [_buildLoaded]'s
    // outer Column, which already appends a [SiteInfoFooter] at the
    // end — so we deliberately do NOT include the footer here, or it
    // would render twice (banner + store info stacked on top of the
    // real footer). The footer's 7-tap admin entry-point stays
    // reachable via the outer Column's footer.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
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

  Widget _buildError(HomeViewModel viewModel) {
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
