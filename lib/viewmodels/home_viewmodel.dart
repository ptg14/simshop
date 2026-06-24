import 'package:flutter/foundation.dart' hide Category;
import '../models/category.dart';
import '../models/product.dart';
import '../services/product_service.dart';

/// ViewModel for the home screen.
class HomeViewModel extends ChangeNotifier {
  /// Constructor allowing optional injection of a product service.
  HomeViewModel({IProductService? productService})
      : _productService = productService ?? RealProductService();

  // Backend service. Inject via constructor in tests; defaults to the real HTTP client.
  final IProductService _productService;

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<String> _categories = [];

  // 2-level hierarchy state.
  final List<String> _largeCategories = [];
  final List<Category> _subCategories = [];
  String _selectedLarge = 'All';
  String _selectedCategory = 'All';

  // Store identifier used to filter products for a specific store.
  String? _selectedStoreId;
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';

  // Getters
  List<Product> get products => _filteredProducts;
  List<String> get categories => _categories;
  List<String> get largeCategories => ['All', ..._largeCategories];
  String get selectedLarge => _selectedLarge;
  String get selectedCategory => _selectedCategory;
  String? get selectedStoreId => _selectedStoreId;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;

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
    await loadProducts();
    await loadCategories();
    await loadLargeCategories();
    await loadSubCategories();
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

  /// Load product categories (flat list — used as a fallback for the legacy UI).
  Future<void> loadCategories() async {
    try {
      final categories = await _productService.getCategories();
      _categories = [...categories];
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load categories: $e';
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

  /// Update the selected store identifier and re‑apply filters.
  void selectStore(String? storeId) {
    if (_selectedStoreId != storeId) {
      _selectedStoreId = storeId;
      _applyFilters();
      notifyListeners();
    }
  }

  /// Search products by query via backend.
  Future<void> searchProducts(String query) async {
    _searchQuery = query;
    // Searching resets both filter levels.
    _selectedLarge = 'All';
    _selectedCategory = 'All';

    if (query.isEmpty) {
      _filteredProducts = _products;
      notifyListeners();
    } else {
      _isLoading = true;
      notifyListeners();

      try {
        _filteredProducts = await _productService.searchProducts(query);
      } catch (e) {
        _error = 'Search failed: $e';
        _filteredProducts = [];
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Reset search and show all products.
  void resetSearch() {
    _searchQuery = '';
    _selectedLarge = 'All';
    _selectedCategory = 'All';
    _filteredProducts = _products;
    notifyListeners();
  }

  /// Apply local store / Large / sub filters on top of already-loaded products.
  void _applyFilters() {
    Iterable<Product> filtered = _products;

    if (_selectedStoreId != null) {
      filtered = filtered.where((p) => p.storeId == _selectedStoreId);
    }

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

  /// Get featured products (on sale).
  List<Product> getFeaturedProducts() =>
      _products.where((product) => product.isOnSale).take(6).toList();

  /// Get promotional products.
  List<Product> getPromotionalProducts() =>
      _products.where((product) => product.rating >= 4.7).take(4).toList();
}
