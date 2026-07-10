import 'package:flutter/foundation.dart' hide Category;
import '../models/category.dart';
import '../models/product.dart';
import '../services/product_service.dart';

/// ViewModel for the home screen.
class HomeViewModel extends ChangeNotifier {
  /// Constructor allowing optional injection of a product service.
  HomeViewModel({
    IProductService? productService,
  }) : _productService = productService ?? RealProductService();

  // Backend service. Inject via constructor in tests; defaults to the real HTTP client.
  final IProductService _productService;

  List<Product> _products = [];
  List<Product> _filteredProducts = [];

  // 2-level hierarchy state.
  final List<String> _largeCategories = [];
  final List<Category> _subCategories = [];
  String _selectedLarge = 'All';

  /// Currently-selected sub-categories. Always non-empty — the
  /// "All <Large>" pseudo-sub is included by default and re-added
  /// whenever the user removes every real sub. Invariant enforced
  /// by [toggleSub] and [selectLarge].
  final Set<String> _selectedSubs = <String>{'All All'};

  /// Optional callback fired from [loadProducts] once the freshly-
  /// fetched list is in place. The home screen wires this to its
  /// image-prefetch helper so the first row of hero images is
  /// already decoded by the time the grid finishes its layout pass.
  /// Notified synchronously after `_filteredProducts` is assigned so
  /// the callback sees the same data the next [notifyListeners] tick
  /// will publish.
  void Function(List<Product> products)? _onProductsLoaded;

  bool _isLoading = false;
  String? _error;

  /// True after [dispose] has run. The three `load*` methods fan
  /// out HTTP requests from [initialize] / explicit refreshes — on
  /// web (especially with hot-restart during dev) those responses
  /// can arrive *after* the widget tree has been torn down. Without
  /// the guard, the late `notifyListeners()` call throws
  /// "ChangeNotifier used after being disposed", which surfaces as
  /// an uncaught promise rejection in the browser console.
  bool _disposed = false;

  // Getters
  List<Product> get products => _filteredProducts;
  List<String> get largeCategories => ['All', ..._largeCategories];
  String get selectedLarge => _selectedLarge;

  /// The sub-categories currently selected. Always non-empty: when
  /// the user has not picked anything specific, this set contains
  /// only the "All <Large>" pseudo-sub for the active Large.
  Set<String> get selectedSubs => Set.unmodifiable(_selectedSubs);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Install a hook that fires once [loadProducts] has populated
  /// `_products` with a fresh list. The home screen uses it to
  /// prefetch the hero images for the first few rows so the grid
  /// doesn't show shimmer placeholders on scroll.
  ///
  /// Pass `null` to detach. Only the most recently installed hook
  /// fires — replacement, not stacking — so re-mounting the home
  /// screen doesn't double-fire the prefetch.
  set onProductsLoaded(void Function(List<Product> products)? hook) {
    _onProductsLoaded = hook;
  }

  /// Sub-categories to display in the second chip row.
  ///
  /// Returns `[]` when "All" Large is selected (caller should hide the row).
  /// Otherwise returns `['All <Large>', ...subs under that Large]`.
  List<String> get visibleSubCategories {
    if (_selectedLarge == 'All') return const [];
    final subs = _subCategories
        .where((c) => c.largeCategory == _selectedLarge)
        .map((c) => c.name)
        .toList()
      ..sort();
    return ['All $_selectedLarge', ...subs];
  }

  /// Initialize the view model and load products.
  ///
  /// Backward-compatible alias for [loadCriticalData] + [loadAuxData]
  /// — kept so pull-to-refresh and existing tests keep working.
  Future<void> initialize() async {
    await Future.wait([
      loadCriticalData(),
      loadAuxData(),
    ]);
    _applyFilters();
  }

  /// Fire the "critical" data wave: products + Large categories.
  ///
  /// These two endpoints are what the home screen needs to render
  /// something useful (grid + filter chips). Firing them as soon as
  /// the first frame paints lets the user see real products without
  /// waiting for the smaller (sub-categories, banners, site-info)
  /// polish endpoints.
  ///
  /// The `loadProducts` failure path flips `_error` and surfaces the
  /// "Không thể tải sản phẩm" screen; `loadLargeCategories` keeps
  /// whatever was previously loaded if the backend is unreachable so
  /// the user can still scroll the grid with the old filter.
  Future<void> loadCriticalData() async {
    await Future.wait([
      loadProducts(),
      loadLargeCategories(),
    ]);
    _applyFilters();
    _notifyIfAlive();
  }

  /// Fire the "aux" wave: sub-categories (used by the second chip
  /// row, hidden until the user picks a Large).
  ///
  /// This can run a frame after [loadCriticalData] without hurting
  /// first paint — the home screen already has products + Large
  /// chips. The aux data finishes filling the rest of the UI in the
  /// background.
  Future<void> loadAuxData() async {
    await loadSubCategories();
    _applyFilters();
    _notifyIfAlive();
  }

  /// Load all products from service.
  Future<void> loadProducts() async {
    _isLoading = true;
    _error = null;

    try {
      _products = await _productService.getAllProducts();
      _filteredProducts = _products;
      // Hand the freshly-loaded products back to whoever mounted us
      // (typically the home screen) so it can prefetch the hero
      // images. We use a callback rather than [notifyListeners]
      // because image decoding is a side-effect of "products
      // arrived", not a UI rebuild hint.
      _onProductsLoaded?.call(_products);
    } catch (e) {
      _error = 'Failed to load products: $e';
      _products = [];
      _filteredProducts = [];
    } finally {
      _isLoading = false;
    }
  }

  /// Fetch the list of Large (parent) categories from the backend.
  Future<void> loadLargeCategories() async {
    try {
      final list = await _productService.getLargeCategories();
      _largeCategories
        ..clear()
        ..addAll(list);
    } catch (_) {
      // Keep previous value on failure.
    }
  }

  /// Fetch all sub-categories with their parent Large category.
  Future<void> loadSubCategories() async {
    try {
      final list = await _productService.getCategoriesWithParent();
      _subCategories
        ..clear()
        ..addAll(list);
    } catch (_) {
      // Keep previous value on failure.
    }
  }

  /// "All <Large>" pseudo-sub for the currently selected Large.
  ///
  /// When `_selectedLarge == 'All'` the Large row is hidden entirely
  /// (see [visibleSubCategories]), so the sub row is never shown
  /// and the value of this helper does not matter — but the
  /// initialiser must still produce a valid string, hence the
  /// placeholder `'All All'`.
  String get _allSubPseudo => 'All $_selectedLarge';

  /// Select a Large category. Resets the sub-category filter to
  /// "All <Large>" because the previously-selected subs may not
  /// belong to the new Large.
  void selectLarge(String large) {
    if (_selectedLarge == large) return;
    _selectedLarge = large;
    _selectedSubs
      ..clear()
      ..add(_allSubPseudo);
    _applyFilters();
    _notifyIfAlive();
  }

  /// Toggle a sub-category in the multi-select set, then re-apply
  /// filters.
  ///
  /// Rules (UX contract):
  ///   • Tapping the "All <Large>" pseudo-sub clears every other
  ///     selection — leaves the set holding only that pseudo-sub.
  ///   • Tapping a real sub that is currently selected removes it.
  ///     If that empties the set, the "All <Large>" pseudo-sub is
  ///     re-added so the user always has at least one pill selected
  ///     (= no way to render an empty filter and show zero products).
  ///   • Tapping a real sub that is not selected adds it and removes
  ///     the "All <Large>" pseudo-sub, since the user has now
  ///     expressed a concrete intent.
  void toggleSub(String sub) {
    final allPseudo = _allSubPseudo;
    if (sub == allPseudo) {
      _selectedSubs
        ..clear()
        ..add(allPseudo);
    } else if (_selectedSubs.contains(sub)) {
      _selectedSubs.remove(sub);
      // Preserve invariant: always at least one entry.
      if (_selectedSubs.isEmpty) {
        _selectedSubs.add(allPseudo);
      }
    } else {
      _selectedSubs
        ..remove(allPseudo)
        ..add(sub);
    }
    _applyFilters();
    _notifyIfAlive();
  }

  /// Apply local Large / sub filters on top of already-loaded products.
  ///
  /// Filter priority (most specific wins):
  ///   1. If the user picked one or more real subs → keep only
  ///      products whose `categories` (or legacy `category`) cover
  ///      **every** selected sub (AND logic — products must have
  ///      all the chosen tags).
  ///   2. Otherwise — only the "All <Large>" pseudo-sub is active
  ///      and a specific Large is selected → keep products whose
  ///      `categories` (or legacy `category`) intersect any sub
  ///      belonging to that Large.
  ///   3. Otherwise → no filtering.
  void _applyFilters() {
    Iterable<Product> filtered = _products;

    // Strip the pseudo-sub if present so the real subs below are
    // the only ones that matter for matching.
    final realSubs = _selectedSubs.where((s) => !s.startsWith('All ')).toSet();

    if (realSubs.isNotEmpty) {
      // Multi-select (AND): product matches only if it belongs to
      // EVERY selected sub. Products missing any one of the chosen
      // tags are filtered out.
      filtered = filtered.where((p) => realSubs.every((s) => _productMatchesSub(p, s)));
    } else if (_selectedLarge != 'All') {
      // "All <Large>" semantics: keep any product under this Large.
      final subsInLarge = _subCategories
          .where((c) => c.largeCategory == _selectedLarge)
          .map((c) => c.name)
          .toSet();
      filtered = filtered.where((p) {
        if (p.categories.any(subsInLarge.contains)) return true;
        // Fallback: match by primary category string for legacy products.
        return subsInLarge.contains(p.category);
      });
    }

    _filteredProducts = filtered.toList();
  }

  /// Returns true when [product] belongs to the given sub-category name,
  /// either via its `categories` list or its primary `category` string.
  bool _productMatchesSub(Product product, String subName) {
    if (product.categories.contains(subName)) return true;
    if (product.category == subName) return true;
    return false;
  }

  /// Wrapper around `notifyListeners` that's a no-op after [dispose].
  /// See [_disposed] for why this exists.
  void _notifyIfAlive() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}