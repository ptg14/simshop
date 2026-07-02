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
  String _selectedCategory = 'All';

  bool _isLoading = false;
  String? _error;

  // Getters
  List<Product> get products => _filteredProducts;
  List<String> get largeCategories => ['All', ..._largeCategories];
  String get selectedLarge => _selectedLarge;
  String get selectedCategory => _selectedCategory;
  bool get isLoading => _isLoading;
  String? get error => _error;

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
  Future<void> initialize() async {
    // Fan-out the three independent endpoints in parallel. Previously
    // these were awaited serially, so the wall-clock cost of the
    // cold-start was the *sum* of all four latencies (often 800ms+
    // on slow networks). With [Future.wait] the cost collapses to
    // the slowest single endpoint. Each load still calls
    // notifyListeners() so consumers update progressively as data
    // arrives — the user sees the category chips appear before the
    // product grid, just as they did before.
    await Future.wait([
      loadProducts(),
      loadLargeCategories(),
      loadSubCategories(),
    ]);
    _applyFilters();
  }

  /// Load all products from service.
  Future<void> loadProducts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _products = await _productService.getAllProducts();
      _filteredProducts = _products;
    } catch (e) {
      _error = 'Failed to load products: $e';
      _products = [];
      _filteredProducts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch the list of Large (parent) categories from the backend.
  Future<void> loadLargeCategories() async {
    try {
      final list = await _productService.getLargeCategories();
      _largeCategories
        ..clear()
        ..addAll(list);
      notifyListeners();
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
      notifyListeners();
    } catch (_) {
      // Keep previous value on failure.
    }
  }

  /// Select a Large category. Resets the sub-category filter to "All".
  void selectLarge(String large) {
    if (_selectedLarge == large) return;
    _selectedLarge = large;
    _selectedCategory = 'All';
    _applyFilters();
    notifyListeners();
  }

  /// Select a sub-category and re-apply filters locally.
  void selectCategory(String category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    _applyFilters();
    notifyListeners();
  }

  /// Apply local Large / sub filters on top of already-loaded products.
  void _applyFilters() {
    Iterable<Product> filtered = _products;

    // Sub-category filter (most specific).
    if (_selectedCategory != 'All' && !_selectedCategory.startsWith('All ')) {
      filtered = filtered.where((p) => _productMatchesSub(p, _selectedCategory));
    } else if (_selectedLarge != 'All') {
      // Filter by any sub-category that belongs to the selected Large.
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
}