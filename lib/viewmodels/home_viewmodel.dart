import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/product_service.dart';

/// ViewModel for the home screen.
class HomeViewModel extends ChangeNotifier {
  final IProductService _productService = MockProductService();

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<String> _categories = [];
  String _selectedCategory = 'All';
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';

  // Getters
  List<Product> get products => _filteredProducts;
  List<String> get categories => _categories;
  String get selectedCategory => _selectedCategory;
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
      _applyFilters();
    } catch (e) {
      _error = 'Failed to load products: $e';
      _products = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load product categories.
  Future<void> loadCategories() async {
    try {
      final categories = await _productService.getCategories();
      _categories = ['All', ...categories];
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load categories: $e';
    }
  }

  /// Select a category and filter products.
  void selectCategory(String category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      _searchQuery = '';
      _applyFilters();
      notifyListeners();
    }
  }

  /// Search products by query.
  Future<void> searchProducts(String query) async {
    _searchQuery = query;
    _selectedCategory = 'All';

    if (query.isEmpty) {
      _filteredProducts = _products;
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
      }
    }

    notifyListeners();
  }

  /// Reset search and show all products.
  void resetSearch() {
    _searchQuery = '';
    _selectedCategory = 'All';
    _filteredProducts = _products;
    notifyListeners();
  }

  /// Apply filters based on selected category and search query.
  void _applyFilters() {
    if (_selectedCategory == 'All') {
      _filteredProducts = _products;
    } else {
      _filteredProducts = _products
          .where((product) => product.category == _selectedCategory)
          .toList();
    }
  }

  /// Get featured products (on sale).
  List<Product> getFeaturedProducts() {
    return _products.where((product) => product.isOnSale).take(6).toList();
  }

  /// Get promotional products.
  List<Product> getPromotionalProducts() {
    return _products.where((product) => product.rating >= 4.7).take(4).toList();
  }
}
