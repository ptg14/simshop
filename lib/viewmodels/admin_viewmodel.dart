import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/store.dart';
import '../services/product_service.dart';

/// ViewModel for admin panel.
class AdminViewModel extends ChangeNotifier {
  /// Constructor allowing optional injection of a product service.
  AdminViewModel({IProductService? productService})
      : _productService = productService ?? RealProductService();

  // Products management via service. Allows injection for testing.
  final IProductService _productService;
  final List<Product> _products = [];
  List<String> _categories = [];

  // Store management (admin can select a store)
  final List<Store> _stores = [];
  Store? _selectedStore;

  // UI states
  bool _isLoading = false;
  String? _error;
  String _selectedTab = 'overview'; // overview, products, categories, settings

  // Getters
  List<Product> get products => _products;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedTab => _selectedTab;
  // Public getters for store data
  List<Store> get stores => _stores;
  Store? get selectedStore => _selectedStore;

  /// Initialize admin view model with products and stores.
  Future<void> initialize() async {
    // Prevent re‑initialisation which would duplicate store entries.
    if (_stores.isNotEmpty) {
      _selectedStore ??= _stores.first;
      return;
    }

    // Load categories from the backend (fallback to static list on error).
    try {
      final categories = await _productService.getCategories();
      _categories = [...categories];
    } catch (_) {
      _categories = ['Design', 'Accessories'];
    }

    // Load products from the backend.
    try {
      final loaded = await _productService.getAllProducts();
      _products.clear();
      _products.addAll(loaded);
    } catch (_) {
      // If backend unavailable, keep empty list.
    }

    // Initialize dummy stores (replace with real service call in production)
    _stores.addAll([
      const Store(id: 'store1', name: 'Cửa hàng 1'),
      const Store(id: 'store2', name: 'Cửa hàng 2'),
    ]);
    _selectedStore = _stores.first;
    notifyListeners();
  }

  /// Select a tab.
  void selectTab(String tab) {
    _selectedTab = tab;
    notifyListeners();
  }

  /// Upload an image (File, XFile, or bytes) and return the URL.
  Future<String?> uploadImage(dynamic file) async {
    try {
      final url = await _productService.uploadImage(file);
      return url;
    } catch (e) {
      _error = 'Lỗi tải ảnh lên: $e';
      return null;
    }
  }

  /// Upload multiple images and return their URLs.
  Future<List<String>?> uploadImages(List<dynamic> files) async {
    try {
      final urls =
          await (_productService as RealProductService).uploadImages(files);
      return urls;
    } catch (e) {
      _error = 'Lỗi tải nhiều ảnh lên: $e';
      return null;
    }
  }

  /// Add a new product.
  Future<void> addProduct(Product product, {dynamic imageFile}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      String? imageUrl = product.imageUrl;
      List<String> images = product.images;

      // Upload images first if provided. Accept either single file or a list.
      if (imageFile != null) {
        if (imageFile is List) {
          final urls = await uploadImages(List<dynamic>.from(imageFile));
          if (urls != null) images = urls;
          if (urls != null && urls.isNotEmpty) imageUrl = urls.first;
        } else {
          final url = await _productService.uploadImage(imageFile);
          if (url != null) {
            images = [url];
            imageUrl = url;
          }
        }
      }

      // Associate product with the currently selected store.
      final productWithStore = product.copyWith(
        storeId: _selectedStore?.id,
        imageUrl: imageUrl,
        images: images,
      );
      // Persist to backend and get the created product with real ID.
      final created = await _productService.createProduct(productWithStore);
      // Update local list with the real product from backend.
      _products.add(created);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi thêm sản phẩm: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update a product.
  Future<void> updateProduct(String id, Product product,
      {dynamic imageFile}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      String? imageUrl = product.imageUrl;
      List<String> images = product.images;

      // Upload new images if provided.
      if (imageFile != null) {
        if (imageFile is List) {
          final urls = await uploadImages(List<dynamic>.from(imageFile));
          if (urls != null) {
            images = urls;
            if (urls.isNotEmpty) imageUrl = urls.first;
          }
        } else {
          final url = await _productService.uploadImage(imageFile);
          if (url != null) {
            images = [url];
            imageUrl = url;
          }
        }
      }

      final updatedProduct =
          product.copyWith(imageUrl: imageUrl, images: images);

      // Persist changes to backend and get the updated product.
      final updated = await _productService.updateProduct(id, updatedProduct);
      final index = _products.indexWhere((p) => p.id == id);
      if (index >= 0) {
        _products[index] = updated;
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi cập nhật sản phẩm: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete a product using the backend API.
  Future<void> deleteProduct(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _productService.deleteProduct(id);
      _products.removeWhere((p) => p.id == id);
    } catch (e) {
      _error = 'Lỗi xóa sản phẩm: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a new category.
  Future<void> addCategory(String category) async {
    try {
      await (_productService as RealProductService).createCategory(category);
      // Refresh categories from backend to ensure persistence and ordering.
      final cats = await _productService.getCategories();
      _categories = ['All', ...cats];
      notifyListeners();
      return;
    } catch (_) {
      // If backend fails, still fall back to local update.
    }
    if (!_categories.contains(category)) {
      _categories.add(category);
      notifyListeners();
    }
  }

  /// Delete a category.
  Future<void> deleteCategory(String category) async {
    if (category == 'All') return;
    try {
      await (_productService as RealProductService).deleteCategory(category);
    } catch (_) {
      // ignore backend delete errors for now
    }
    _categories.remove(category);
    notifyListeners();
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
      'totalCategories': _categories.length,
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
