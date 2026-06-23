import 'package:flutter/foundation.dart';
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
  String _selectedCategory = 'All';
  // Store identifier used to filter products for a specific store.
  String? _selectedStoreId;
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';

  // Getters
  List<Product> get products => _filteredProducts;
  List<String> get categories => _categories;
  String get selectedCategory => _selectedCategory;
  String? get selectedStoreId => _selectedStoreId;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  /// Initialize the view model and load products.
  Future<void> initialize() async {
    await loadProducts();
    await loadCategories();
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

  /// Load product categories.
  Future<void> loadCategories() async {
    try {
      final categories = await _productService.getCategories();
      _categories = [...categories];
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load categories: $e';
    }
  }

  /// Select a category and filter products via backend.
  Future<void> selectCategory(String category) async {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      _searchQuery = '';
      _isLoading = true;
      notifyListeners();

      try {
        if (category == 'All') {
          _filteredProducts = _products;
        } else {
          _filteredProducts =
              await _productService.getProductsByCategory(category);
        }
      } catch (e) {
        _error = 'Failed to filter by category: $e';
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }
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
    _selectedCategory = 'All';
    _filteredProducts = _products;
    notifyListeners();
  }

  /// Apply local store filter on top of already-loaded products.
  void _applyFilters() {
    Iterable<Product> filtered = _products;

    if (_selectedStoreId != null) {
      filtered = filtered.where((p) => p.storeId == _selectedStoreId);
    }

    _filteredProducts = filtered.toList();
  }

  /// Get featured products (on sale).
  List<Product> getFeaturedProducts() =>
      _products.where((product) => product.isOnSale).take(6).toList();

  /// Get promotional products.
  List<Product> getPromotionalProducts() =>
      _products.where((product) => product.rating >= 4.7).take(4).toList();
}
