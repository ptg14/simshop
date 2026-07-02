import 'package:flutter/foundation.dart' hide Category;
import '../models/category.dart';
import '../models/product.dart';
import '../services/_http_with_admin_token.dart';
import '../services/product_service.dart';

/// ViewModel for admin panel.
class AdminViewModel extends ChangeNotifier {
  /// Constructor allowing optional injection of a product service.
///
/// In production [main.dart] passes the shared [IProductService]
/// (which already has [IAdminAuthService] injected) so admin write
/// requests carry `Authorization: Bearer ...`. If both args are
/// null — only in tests — the constructor falls back to plain
/// unauthenticated services, which the backend will reject with
/// 401.
  AdminViewModel({
    IProductService? productService,
  }) : _productService = productService ?? RealProductService();

  // Products management via service. Allows injection for testing.
  final IProductService _productService;
  final List<Product> _products = [];

  // 2-level category hierarchy.
  final List<String> _largeCategories = [];
  final List<Category> _subCategories = [];
  String? _selectedLargeCategory;

  // UI states
  bool _isLoading = false;
  String? _error;
  // True after a write returned 401 "admin session required".
  // Set when the cached Bearer token no longer matches the
  // server-side session map (server restart, 24h TTL elapsed,
  // etc.). The admin shell watches this and pops back to
  // [AdminAuthGate] so the user can re-authenticate before
  // retrying.
  bool _adminSessionExpired = false;
  String _selectedTab = 'products'; // products, categories, articles, events, settings

  // Getters
  List<Product> get products => _products;
  List<String> get largeCategories => List.unmodifiable(_largeCategories);
  List<Category> get subCategories => List.unmodifiable(_subCategories);
  String? get selectedLargeCategory => _selectedLargeCategory;
  bool get isLoading => _isLoading;
  String? get error => _error;
  /// True after a write failed because the cached Bearer token is no
  /// longer valid server-side. The admin shell watches this and
  /// pops back to [AdminAuthGate] to let the user re-authenticate.
  bool get adminSessionExpired => _adminSessionExpired;
  String get selectedTab => _selectedTab;

  /// Initialize admin view model with products.
  Future<void> initialize() async {
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

    notifyListeners();
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

      // Persist to backend and get the created product with real ID.
      final created = await _productService.createProduct(
        product.copyWith(imageUrl: imageUrl, images: images),
      );
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
    _adminSessionExpired = false;
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
      if (e is AdminSessionExpiredException) {
        // Cached token is dead (server restart, TTL elapsed). The
        // shell listens for [adminSessionExpired] and routes back
        // to the auth gate so the user can re-auth.
        _adminSessionExpired = true;
        _error = e.message;
      } else {
        _error = 'Lỗi cập nhật sản phẩm: $e';
      }
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
}