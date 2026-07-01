import 'package:flutter/foundation.dart' hide Category;
import '../models/category.dart';
import '../models/product.dart';
import '../models/store.dart';
import '../services/analytics_service.dart';
import '../services/product_service.dart';

/// ViewModel for admin panel.
class AdminViewModel extends ChangeNotifier {
  /// Constructor allowing optional injection of a product service.
  AdminViewModel({
    IProductService? productService,
    IAnalyticsService? analyticsService,
  })  : _productService = productService ?? RealProductService(),
        _analyticsService = analyticsService ?? RealAnalyticsService();

  // Products management via service. Allows injection for testing.
  final IProductService _productService;
  // Analytics — used for the overview's total visits + top products.
  final IAnalyticsService _analyticsService;
  final List<Product> _products = [];
  List<String> _categories = [];

  // 2-level category hierarchy. The flat [_categories] list is kept for the
  // legacy picker / counts; structured lists are used by the new picker and
  // categories management screen.
  final List<String> _largeCategories = [];
  final List<Category> _subCategories = [];
  String? _selectedLargeCategory;

  // Store management (admin can select a store)
  final List<Store> _stores = [];
  Store? _selectedStore;

  // UI states
  bool _isLoading = false;
  String? _error;
  String _selectedTab = 'overview'; // overview, products, categories, articles, settings

  // Analytics summary for the admin overview card.
  int _totalVisits = 0;
  List<TopProductView> _topProducts = const [];

  // Getters
  List<Product> get products => _products;
  List<String> get categories => _categories;
  List<String> get largeCategories => List.unmodifiable(_largeCategories);
  List<Category> get subCategories => List.unmodifiable(_subCategories);
  String? get selectedLargeCategory => _selectedLargeCategory;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedTab => _selectedTab;
  int get totalVisits => _totalVisits;
  List<TopProductView> get topProducts => _topProducts;
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

    // Load structured category hierarchy (Large + subs with parent).
    await loadLargeCategories();
    await loadSubCategories();

    // Initialize dummy stores (replace with real service call in production)
    _stores.addAll([
      const Store(id: 'store1', name: 'Cửa hàng 1'),
      const Store(id: 'store2', name: 'Cửa hàng 2'),
    ]);
    _selectedStore = _stores.first;
    notifyListeners();

    // Analytics is non-critical — failures must not block the dashboard.
    await loadAnalyticsSummary();
  }

  /// Fetch the analytics summary for the admin overview card.
  ///
  /// Errors are swallowed: tracking failure should never break the
  /// admin dashboard. The UI then renders zeros + an empty list.
  Future<void> loadAnalyticsSummary() async {
    try {
      final summary = await _analyticsService.getSummary(topN: 5);
      _totalVisits = summary.totalVisits;
      _topProducts = summary.topProducts;
      notifyListeners();
    } catch (_) {
      // Keep the previous values (likely zeros) on failure.
    }
  }

  /// Select a tab.
  void selectTab(String tab) {
    _selectedTab = tab;
    notifyListeners();
  }

  /// Set the active Large category for the admin product-form picker.
  void selectLargeCategory(String? name) {
    if (_selectedLargeCategory != name) {
      _selectedLargeCategory = name;
      notifyListeners();
    }
  }

  /// Fetch the list of Large categories from the backend.
  Future<void> loadLargeCategories() async {
    try {
      final list = await _productService.getLargeCategories();
      _largeCategories
        ..clear()
        ..addAll(list);
      notifyListeners();
    } catch (_) {
      // Keep previous value on failure; do not block the admin screen.
    }
  }

  /// Fetch all sub-categories together with their parent Large category.
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

  /// Persist a new Large category and refresh local state.
  /// Returns true on success.
  Future<bool> addLargeCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    try {
      await (_productService as RealProductService)
          .createLargeCategory(trimmed);
    } catch (_) {
      return false;
    }
    if (!_largeCategories.contains(trimmed)) {
      _largeCategories.add(trimmed);
      _largeCategories.sort();
      _selectedLargeCategory = trimmed;
    }
    notifyListeners();
    return true;
  }

  /// Delete a Large category. Its subs become orphans (`largeCategory == null`).
  /// Returns true on success.
  Future<bool> deleteLargeCategory(String name) async {
    try {
      await (_productService as RealProductService).deleteLargeCategory(name);
    } catch (_) {
      return false;
    }
    _largeCategories.remove(name);
    if (_selectedLargeCategory == name) _selectedLargeCategory = null;
    // Mark the sub's parent as null without a backend round-trip — the FK
    // ON DELETE SET NULL will already have done it.
    for (var i = 0; i < _subCategories.length; i++) {
      if (_subCategories[i].largeCategory == name) {
        _subCategories[i] = Category(
          name: _subCategories[i].name,
          largeCategory: null,
        );
      }
    }
    notifyListeners();
    return true;
  }

  /// Add a new sub-category under [largeCategoryName] and refresh state.
  /// Auto-selects the new sub. Returns true on success.
  Future<bool> addCategoryWithParent(
      String name, String largeCategoryName) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || largeCategoryName.isEmpty) return false;
    try {
      await (_productService as RealProductService)
          .createCategoryWithParent(trimmed, largeCategoryName);
    } catch (_) {
      return false;
    }
    // Refresh sub-categories list to reflect the new row.
    await loadSubCategories();
    return true;
  }

  /// Remove a sub-category by name. Returns true on success.
  Future<bool> deleteSubCategory(String name) async {
    try {
      await (_productService as RealProductService).deleteCategory(name);
    } catch (_) {
      return false;
    }
    _subCategories.removeWhere((c) => c.name == name);
    _categories.remove(name);
    notifyListeners();
    return true;
  }

  /// Upload an image (File, XFile, or bytes) and return the URL.
  ///
  /// [productName] / [productId] / [startIndex] are forwarded to the
  /// backend so the server can build a descriptive filename
  /// (`YYYYMMDD-<slug>-<index>.<ext>`).
  Future<String?> uploadImage(
    dynamic file, {
    String? productName,
    String? productId,
    int startIndex = 1,
  }) async {
    try {
      final url = await _productService.uploadImage(
        file,
        productName: productName,
        productId: productId,
        startIndex: startIndex,
      );
      return url;
    } catch (e) {
      _error = 'Lỗi tải ảnh lên: $e';
      return null;
    }
  }

  /// Upload multiple images and return their URLs.
  Future<List<String>?> uploadImages(
    List<dynamic> files, {
    String? productName,
    String? productId,
    int startIndex = 1,
  }) async {
    try {
      final urls = await (_productService as RealProductService).uploadImages(
        files,
        productName: productName,
        productId: productId,
        startIndex: startIndex,
      );
      return urls;
    } catch (e) {
      _error = 'Lỗi tải nhiều ảnh lên: $e';
      return null;
    }
  }

  /// Add a new product.
  ///
  /// Image handling mirrors [updateProduct]: any pre-existing
  /// `product.images` is preserved, and newly uploaded files are
  /// *appended* (not used to replace). Previously this method
  /// overwrote `images` with the upload result, silently dropping
  /// every existing picture whenever the admin uploaded even a
  /// single new file — the same class of bug that lived in
  /// `updateProduct` until the matching fix there. Aligning the
  /// two methods keeps callers from having to remember a hidden
  /// behavioural difference between create and update.
  Future<void> addProduct(Product product, {dynamic imageFile}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // [Product.imageUrl] is a non-nullable [String], but the
      // create-flow form may submit it as empty when the admin
      // hasn't chosen a hero yet. Treat the empty string as "no
      // existing hero" so we can fall back to the first uploaded
      // file below.
      String imageUrl = product.imageUrl;
      final List<String> images = List<String>.from(product.images);

      // Upload images first if provided. Accept either single file or a list.
      if (imageFile != null) {
        // Pass the (user-entered) name so the backend can build
        // descriptive filenames. No productId yet — backend derives a
        // short hash from the name+random suffix.
        if (imageFile is List) {
          final urls = await uploadImages(
            List<dynamic>.from(imageFile),
            productName: product.name,
          );
          if (urls != null && urls.isNotEmpty) {
            images.addAll(urls);
            if (imageUrl.isEmpty) imageUrl = urls.first;
          }
        } else {
          final url = await _productService.uploadImage(
            imageFile,
            productName: product.name,
          );
          if (url != null) {
            images.add(url);
            if (imageUrl.isEmpty) imageUrl = url;
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
      // [Product.imageUrl] is non-nullable but the form may submit it
      // as empty. An empty string here means "no existing hero, pick
      // the first uploaded file" rather than "blank the hero". An
      // existing non-empty value wins so admins can re-order the
      // gallery without the hero getting overwritten on every save.
      String imageUrl = product.imageUrl;
      // Start from the product's existing images and append any
      // newly-uploaded ones. Previously this was overwritten with
      // `images = urls`, which silently dropped every existing
      // picture whenever the admin uploaded even a single new file.
      // The same bug existed in the single-file branch (`images =
      // [url]`) — fixed by appending instead of replacing.
      final List<String> images = List<String>.from(product.images);

      // Upload new images if provided. For updates we have a known ID
      // and the new name — both are sent so the backend can slug them.
      if (imageFile != null) {
        if (imageFile is List) {
          final urls = await uploadImages(
            List<dynamic>.from(imageFile),
            productName: product.name,
            productId: id,
          );
          if (urls != null && urls.isNotEmpty) {
            images.addAll(urls);
            if (imageUrl.isEmpty) imageUrl = urls.first;
          }
        } else {
          final url = await _productService.uploadImage(
            imageFile,
            productName: product.name,
            productId: id,
          );
          if (url != null) {
            images.add(url);
            if (imageUrl.isEmpty) imageUrl = url;
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
  ///
  /// When no store is selected, fall back to the full product list
  /// (the app is single-store; the original filter-by-null was a
  /// 0-stats bug that left the dashboard empty before the user picked
  /// a store).
  Map<String, dynamic> getDashboardStats() {
    final storeProducts = _selectedStore == null
        ? _products
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
