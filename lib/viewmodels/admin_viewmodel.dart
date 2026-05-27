import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/store.dart';

/// ViewModel for admin panel.
class AdminViewModel extends ChangeNotifier {
  // Authentication
  bool _isLoggedIn = false;
  final String _adminUsername = 'admin';
  final String _adminPassword = 'admin123'; // In production, use secure storage

  // Products management
  final List<Product> _products = [];
  List<String> _categories = [];

  // Store management (admin can select a store)
  final List<Store> _stores = [];
  Store? _selectedStore;

  // UI states
  bool _isLoading = false;
  String? _error;
  String _selectedTab =
      'overview'; // overview, products, categories, analytics, settings

  // Getters
  bool get isLoggedIn => _isLoggedIn;
  List<Product> get products => _products;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedTab => _selectedTab;
  // Public getters for store data
  List<Store> get stores => _stores;
  Store? get selectedStore => _selectedStore;

  /// Initialize admin view model with products.
  Future<void> initialize() async {
    // Prevent re‑initialisation which would duplicate store entries.
    if (_stores.isNotEmpty) {
      // Already initialized; ensure a selected store exists.
      _selectedStore ??= _stores.first;
      return;
    }

    // Initialize dummy categories (replace with real service call in production)
    _categories = ['All', 'PC Gaming', 'PC Design', 'PC Accessories'];

    // Initialize dummy stores (replace with real service call in production)
    _stores.addAll([
      const Store(id: 'store1', name: 'Cửa hàng 1'),
      const Store(id: 'store2', name: 'Cửa hàng 2'),
    ]);
    // Ensure a store is selected after initialization.
    _selectedStore = _stores.first;
    notifyListeners();
  }

  /// Login with username and password.
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 500));

      if (username == _adminUsername && password == _adminPassword) {
        _isLoggedIn = true;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Tên đăng nhập hoặc mật khẩu không chính xác';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Lỗi đăng nhập: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logout.
  void logout() {
    _isLoggedIn = false;
    _selectedTab = 'products';
    notifyListeners();
  }

  /// Select a tab.
  void selectTab(String tab) {
    _selectedTab = tab;
    notifyListeners();
  }

  /// Add a new product.
  Future<void> addProduct(Product product) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      // Associate product with the currently selected store (using category field as placeholder)
      // Associate product with the currently selected store using storeId.
      final productWithStore = product.copyWith(
        storeId: _selectedStore?.id,
        // Keep category unchanged; it represents product category.
      );
      _products.add(productWithStore);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi thêm sản phẩm: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update a product.
  Future<void> updateProduct(String id, Product product) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final index = _products.indexWhere((p) => p.id == id);
      if (index >= 0) {
        _products[index] = product;
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi cập nhật sản phẩm: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete a product.
  Future<void> deleteProduct(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      _products.removeWhere((p) => p.id == id);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi xóa sản phẩm: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a new category.
  Future<void> addCategory(String category) async {
    if (!_categories.contains(category)) {
      _categories.add(category);
      notifyListeners();
    }
  }

  /// Delete a category.
  Future<void> deleteCategory(String category) async {
    if (category != 'All') {
      _categories.remove(category);
      notifyListeners();
    }
  }

  /// Get dashboard statistics.
  Map<String, dynamic> getDashboardStats() {
    // Filter products belonging to the selected store
    // Filter products belonging to the selected store using storeId.
    final storeProducts = _selectedStore == null
        ? []
        : _products.where((p) => p.storeId == _selectedStore!.id).toList();
    return {
      'totalProducts': storeProducts.length,
      'totalCategories': _categories.length - 1, // Exclude "All"
      'productsOnSale': storeProducts.where((p) => p.isOnSale).length,
      'lowStockProducts':
          storeProducts.where((p) => (p.stock ?? 0) < 10).length,
    };
  }

  /// Select a store for the admin session.
  void selectStore(String storeId) {
    // Find the store with the given ID. If not found, keep the current selection.
    for (final s in _stores) {
      if (s.id == storeId) {
        _selectedStore = s;
        notifyListeners();
        return;
      }
    }
    // No matching store; do not change selection.
    notifyListeners();
  }
}
