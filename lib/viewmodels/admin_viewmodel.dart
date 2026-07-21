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

  // Product-list filter state. Mirrors the home menu filter (Large +
  // sub-categories), with one extra bucket: "Chưa phân loại" — every
  // orphan sub (largeCategory == null) is grouped under a single
  // synthetic Large so admins can find products that have no parent
  // assigned without having to scroll every orphan tag.
  //
  // [filterLarge] uses one of three shapes:
  //   • null         → no Large picked (show every product)
  //   • '__orphans__'→ the orphan bucket; subs = orphan subs
  //   • any string   → a real Large from [_largeCategories]
  //
  // [filterSelectedSubs] is the AND-set the admin has picked. When
  // empty AND [filterLarge] is not null, the implicit "All <Large>"
  // semantics apply (any product under that Large).
  String? _filterLarge;
  final Set<String> _filterSelectedSubs = <String>{};

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
  List<Product> get products => _filteredProducts;
  List<String> get largeCategories => List.unmodifiable(_largeCategories);
  List<Category> get subCategories => List.unmodifiable(_subCategories);
  String? get selectedLargeCategory => _selectedLargeCategory;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Sentinel value for [filterLarge] that represents the
  /// "Chưa phân loại" / orphan bucket. Admin products screen surfaces
  /// this as the first tag on the Large row alongside the real Larges.
  /// We use a dedicated constant instead of a bare `null` because
  /// `null` already means "no filter / all products", and we need a
  /// distinct UI state for "orphan bucket selected".
  static const String orphanBucket = '__orphans__';

  /// Currently active filter Large. See the field comment for the
  /// three possible shapes.
  String? get filterLarge => _filterLarge;

  /// Sub-categories currently selected inside [filterLarge]. AND
  /// across the set; empty set means "All <Large>".
  Set<String> get filterSelectedSubs => Set.unmodifiable(_filterSelectedSubs);

  /// Sub-categories to display in the second chip row of the admin
  /// product filter. Returns `[]` when no Large is picked (caller
  /// hides the row).
  ///
  /// For the orphan bucket this returns every orphan sub sorted by
  /// name, with no "All Chưa phân loại" pseudo-sub prefix — there's
  /// only one orphan bucket so the prefix would be visual noise.
  List<String> get visibleFilterSubs {
    final l = _filterLarge;
    if (l == null) return const [];
    if (l == orphanBucket) {
      final subs = _subCategories
          .where((c) => c.largeCategory == null)
          .map((c) => c.name)
          .toList()
        ..sort();
      return ['Tất cả', ...subs];
    }
    final subs = _subCategories
        .where((c) => c.largeCategory == l)
        .map((c) => c.name)
        .toList()
      ..sort();
    return ['Tất cả $l', ...subs];
  }

  /// Filtered product list for the admin product screen.
  ///
  /// Mirrors the home menu logic with one extension: when
  /// [filterLarge] is [orphanBucket], products are matched against
  /// orphan subs (largeCategory == null) instead of subs parented
  /// to a real Large. See `_applyFilter` for the matching rules.
  final List<Product> _filteredProducts = [];

  /// True when at least one real sub (not the pseudo-sub) is
  /// selected. Used by the filter widget to render the sub-row
  /// pills with their `selected` flag — a pseudo-sub being
  /// "selected" alone means "all under this Large", not "filtered".
  bool get hasActiveFilterSub => _filterSelectedSubs.any(
        (s) => s != 'Tất cả' && !s.startsWith('Tất cả '),
      );

  /// Render the Large row's pills. Includes a synthetic
  /// "Chưa phân loại" pill at the end whenever at least one orphan
  /// sub exists. The admin screen paints this row separately; the
  /// view-model just supplies the labels + selection state.
  List<String> get filterLargePills {
    final pills = <String>[..._largeCategories];
    if (_subCategories.any((c) => c.largeCategory == null)) {
      pills.add(orphanBucket);
    }
    return pills;
  }

  /// Display label for the orphan-bucket pill. Distinct from the
  /// internal [orphanBucket] sentinel so users see Vietnamese copy
  /// while the view-model uses a stable key for comparisons.
  static const String orphanBucketLabel = 'Chưa phân loại';

  /// Localized label for any Large tag on the admin filter row,
  /// translating the [orphanBucket] sentinel to [orphanBucketLabel].
  String labelForFilterLarge(String key) =>
      key == orphanBucket ? orphanBucketLabel : key;
  /// True after a write failed because the cached Bearer token is no
  /// longer valid server-side. The admin shell watches this and
  /// pops back to [AdminAuthGate] to let the user re-authenticate.
  bool get adminSessionExpired => _adminSessionExpired;

  /// Force-clear the [adminSessionExpired] flag without performing
  /// any I/O. Called by [AdminShell] in [State.initState] when a
  /// fresh shell mounts after the user came back through the auth
  /// gate — without this the flag stays sticky on the shared
  /// root-level VM and the very first build redirects back to the
  /// gate, producing an admin ↔ gate loop. Callers MUST NOT use
  /// this to mask a real mid-session 401; the shell only invokes
  /// it once per fresh [State].
  ///
  /// Does NOT call [notifyListeners]: at the moment this runs the
  /// shell is still inside `initState`, so any listener rebuild
  /// would be a "setState during build" violation. The shell's own
  /// first build reads the now-cleared flag directly, which is
  /// exactly what we want.
  void clearAdminSessionExpired() {
    _adminSessionExpired = false;
  }

  String get selectedTab => _selectedTab;

  /// Initialize admin view model with products.
  ///
  /// Called from the admin product screen on first mount (see
  /// [AdminProductsScreen.initState]) and from the "Thử lại" (retry)
  /// button in the error view (see
  /// `lib/views/admin/admin_product/admin_product_screen.dart:112`).
  ///
  /// On entry we reset [_error] so a stale message from a prior
  /// failed write doesn't keep the error view painted after a
  /// successful retry — without this reset the retry button has no
  /// visible effect, because `_buildBody` checks `viewModel.error !=
  /// null` to decide between the error screen and the loaded grid.
  /// Mirrors the `_error = null` reset that
  /// [HomeViewModel.loadProducts] performs for the same reason (the
  /// home "Thử lại" button already worked; admin was the broken one).
  Future<void> initialize() async {
    // Clear any stale error before the load so a successful retry
    // actually un-sticks the error view.
    _error = null;

    // Load products from the backend. Capture the failure into
    // [_error] (instead of silently swallowing it with `catch (_)`)
    // so the admin screen surfaces a "Không thể tải sản phẩm" view
    // with a retry button — matching the HomeViewModel behaviour and
    // matching what the user expects when the load fails.
    try {
      final loaded = await _productService.getAllProducts();
      _products.clear();
      _products.addAll(loaded);
    } catch (e) {
      _error = 'Lỗi tải sản phẩm: $e';
    }

    // Load structured category hierarchy (Large + subs with parent).
    // Both helpers keep their previous values on failure and never
    // overwrite [_error] — they're nice-to-have polish for the
    // filter row, not the load that gates the admin grid.
    await loadLargeCategories();
    await loadSubCategories();

    _applyAdminFilter();
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

  // ---------------------------------------------------------------------------
  // Admin product-list filter
  // ---------------------------------------------------------------------------

  /// Reset every filter selection. Useful for the "clear all" link
  /// on the filter widget. Idempotent: calling twice is a no-op.
  void clearFilter() {
    if (_filterLarge == null && _filterSelectedSubs.isEmpty) return;
    _filterLarge = null;
    _filterSelectedSubs.clear();
    _applyAdminFilter();
    notifyListeners();
  }

  /// Select the Large tag for the admin product-list filter.
  ///
  /// Pass [orphanBucket] for the "Chưa phân loại" tag; pass `null`
  /// to drop the Large filter entirely; pass any other string for a
  /// real Large.
  ///
  /// Always resets the sub-set so a previously-selected sub under
  /// one Large doesn't bleed into the new selection (matches
  /// `HomeViewModel.selectLarge`).
  void selectFilterLarge(String? large) {
    if (_filterLarge == large) return;
    _filterLarge = large;
    _filterSelectedSubs.clear();
    _applyAdminFilter();
    notifyListeners();
  }

  /// Toggle a sub-category in the admin filter's AND-set.
  ///
  /// Mirrors `HomeViewModel.toggleSub`: tapping the "All <Large>"
  /// pseudo clears every real selection; tapping a real sub that is
  /// already in the set removes it (re-adding the pseudo so the set
  /// is never empty); tapping a real sub not in the set adds it and
  /// removes the pseudo. The pseudo-sub's exact text depends on
  /// whether [filterLarge] is [orphanBucket] or a real Large — see
  /// [visibleFilterSubs] for the source of truth.
  void toggleFilterSub(String sub) {
    final l = _filterLarge;
    if (l == null) {
      // No Large selected — sub taps are ignored. The UI hides the
      // sub row in this state, but guard defensively.
      return;
    }
    final allPseudo = l == orphanBucket ? 'Tất cả' : 'Tất cả $l';
    if (sub == allPseudo) {
      _filterSelectedSubs
        ..clear()
        ..add(allPseudo);
    } else if (_filterSelectedSubs.contains(sub)) {
      _filterSelectedSubs.remove(sub);
      if (_filterSelectedSubs.isEmpty) {
        _filterSelectedSubs.add(allPseudo);
      }
    } else {
      _filterSelectedSubs
        ..remove(allPseudo)
        ..add(sub);
    }
    _applyAdminFilter();
    notifyListeners();
  }

  /// Apply [filterLarge] / [filterSelectedSubs] to [_products] and
  /// materialise the result into [_filteredProducts].
  ///
  /// Logic mirrors `HomeViewModel._applyFilters`, with one
  /// extension: the orphan bucket matches against subs with
  /// `largeCategory == null` instead of subs parented to a real
  /// Large.
  void _applyAdminFilter() {
    final l = _filterLarge;
    if (l == null) {
      _filteredProducts
        ..clear()
        ..addAll(_products);
      return;
    }
    final subPool = l == orphanBucket
        ? _subCategories
            .where((c) => c.largeCategory == null)
            .map((c) => c.name)
            .toSet()
        : _subCategories
            .where((c) => c.largeCategory == l)
            .map((c) => c.name)
            .toSet();
    final realSubs =
        _filterSelectedSubs.where((s) => !_isFilterAllPseudo(s)).toSet();
    Iterable<Product> filtered = _products;
    if (realSubs.isNotEmpty) {
      // AND across selected subs.
      filtered = filtered.where(
        (p) => realSubs.every((s) => _adminSubMatches(p, s)),
      );
    } else {
      // "All <Large>" pseudo-sub → keep products whose category set
      // intersects the pool.
      filtered = filtered.where((p) {
        if (p.categories.any(subPool.contains)) return true;
        return subPool.contains(p.category);
      });
    }
    _filteredProducts
      ..clear()
      ..addAll(filtered);
  }

  /// True when [sub] is the "All <Large>" pseudo-sub that represents
  /// "no specific sub selected, just keep everything under this
  /// Large". Used by [_applyAdminFilter] to strip the pseudo-sub out
  /// of the AND-set when computing the real selection.
  bool _isFilterAllPseudo(String sub) =>
      sub == 'Tất cả' || sub.startsWith('Tất cả ');

  /// True when [product] has [subName] in either its `categories`
  /// multi-list or its legacy primary `category` string.
  bool _adminSubMatches(Product product, String subName) {
    if (product.categories.contains(subName)) return true;
    if (product.category == subName) return true;
    return false;
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
      await _productService.createLargeCategory(trimmed);
    } on AdminSessionExpiredException catch (e) {
      // Cached Bearer token is dead (server restart, TTL elapsed).
      // Mirror [addProduct]: the shell listens for
      // [_adminSessionExpired] and routes back to the auth gate so
      // the user can re-auth — without this branch the user just
      // sees the dialog close silently with no hint why.
      _adminSessionExpired = true;
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Lỗi thêm danh mục lớn: $e';
      notifyListeners();
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
      await _productService.deleteLargeCategory(name);
    } on AdminSessionExpiredException catch (e) {
      _adminSessionExpired = true;
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Lỗi xóa danh mục lớn: $e';
      notifyListeners();
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
  ///
  /// Pass an empty [largeCategoryName] to create an orphan sub
  /// (one with no parent Large). The admin "Khác" bucket in the
  /// categories screen, and the "-- Chọn danh mục lớn --" slot in
  /// the product picker, both surface orphan subs — so admins need
  /// a way to mint them without first parenting them.
  Future<bool> addCategoryWithParent(
      String name, String largeCategoryName) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    try {
      // Both paths hit the same backend endpoint (POST /api/categories).
      // An empty parent string routes through
      // [AddCategoryWithParent] → `AddCategory` on the server, which
      // creates an orphan row (large_category_id IS NULL). Keep the
      // empty/large branches together so the call shape is identical
      // and any future "large_category" middleware change reaches
      // both.
      await _productService
          .createCategoryWithParent(trimmed, largeCategoryName);
    } on AdminSessionExpiredException catch (e) {
      _adminSessionExpired = true;
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Lỗi thêm danh mục con: $e';
      notifyListeners();
      return false;
    }
    // Refresh sub-categories list to reflect the new row.
    await loadSubCategories();
    return true;
  }

  /// Remove a sub-category by name. Returns true on success.
  Future<bool> deleteSubCategory(String name) async {
    try {
      await _productService.deleteCategory(name);
    } on AdminSessionExpiredException catch (e) {
      _adminSessionExpired = true;
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Lỗi xóa danh mục con: $e';
      notifyListeners();
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
      final urls = await _productService.uploadImages(
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
  ///
  /// [imageOrder] is the explicit ordering for the resulting
  /// `images` list. When supplied (e.g. by the dialog after a
  /// drag-reorder) the VM writes it verbatim, mixing already-
  /// uploaded URLs and freshly-uploaded URLs in the order the
  /// admin chose. When `null` the VM falls back to the legacy
  /// behaviour of "preserve existing `product.images` then append
  /// the new uploads" — used by callers that don't care about
  /// order.
  Future<void> addProduct(Product product,
      {dynamic imageFile,
      List<String>? removedImageUrls,
      List<String>? imageOrder}) async {
    _isLoading = true;
    _error = null;
    // Clear any stale "session expired" flag from a prior failure so
    // a successful retry isn't treated as session-expired by the
    // shell. [updateProduct] below already does this on entry; mirror
    // it here so the create/update twins behave identically. Without
    // this reset, a 401 in one session leaves the flag stuck `true`
    // on the shared [AdminViewModel] instance (it lives at the root
    // MultiProvider, not on the AdminShell), and the very next
    // successful createProduct pops the admin back to the auth gate
    // — an admin ↔ gate loop that locks the user out of their own
    // dashboard.
    _adminSessionExpired = false;
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

      // Caller-supplied explicit ordering wins over the
      // "preserve + append" default. The dialog passes this after a
      // drag-reorder so newly-uploaded images can sit at the
      // position the admin chose (including position 0 to become
      // the cover), not at the tail of the list.
      if (imageOrder != null) {
        images
          ..clear()
          ..addAll(imageOrder);
        // Caller-supplied order is authoritative for both the
        // gallery and the cover: an empty [imageOrder] means the
        // admin removed every image and we must clear [imageUrl]
        // too — otherwise we'd leave a stale URL on a product
        // whose gallery is empty.
        imageUrl = images.isNotEmpty ? images.first : '';
      }

      // Persist to backend and get the created product with real ID.
      // [removedImageUrls] is normally null/empty on create — there's
      // no pre-existing gallery to prune. The parameter is plumbed
      // through for symmetry with [updateProduct] so the dialog can
      // use a single call shape for both flows.
      final created = await _productService.createProduct(
        product.copyWith(imageUrl: imageUrl, images: images),
        removedImageUrls: removedImageUrls,
      );
      // Update local list with the real product from backend.
      _products.add(created);
      _applyAdminFilter();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      // Mirror [updateProduct] below: when the cached Bearer token is
      // no longer valid (server restart, TTL elapsed, etc.) the
      // service layer throws [AdminSessionExpiredException] via
      // [detectAdminSessionExpiry] in `_http_with_admin_token.dart`.
      // Without this branch the user gets stuck on a dead session —
      // a generic "Lỗi thêm sản phẩm: ..." string — and the admin
      // shell never pops them back to the auth gate. The shell
      // watches [adminSessionExpired] (see [AdminShell.build]) and
      // routes through `Navigator.pushAndRemoveUntil` when it's true.
      if (e is AdminSessionExpiredException) {
        _adminSessionExpired = true;
        _error = e.message;
      } else {
        _error = 'Lỗi thêm sản phẩm: $e';
      }
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update a product.
  ///
  /// [removedImageUrls] collects image URLs the admin dropped from
  /// the gallery. Forwarded to the backend, which best-effort
  /// deletes each underlying file from /uploads/ after the DB UPDATE
  /// commits — see RealProductService.updateProduct for the body
  /// assembly.
  ///
  /// [imageOrder] is the explicit ordering for the resulting
  /// `images` list. When supplied (e.g. by the dialog after a
  /// drag-reorder) the VM writes it verbatim — already-uploaded
  /// URLs and freshly-uploaded URLs in the order the admin chose.
  /// When `null` the VM falls back to "preserve `product.images`
  /// then append new uploads", the legacy behaviour for callers
  /// that don't care about order. The dialog passes `null` for
  /// [imageFile] alongside a populated [imageOrder] because it
  /// has already uploaded the new bytes itself and just needs the
  /// VM to persist the final list shape.
  Future<void> updateProduct(String id, Product product,
      {dynamic imageFile,
      List<String>? removedImageUrls,
      List<String>? imageOrder}) async {
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

      // Caller-supplied explicit ordering wins over the
      // "preserve + append" default. The dialog passes this after a
      // drag-reorder so newly-uploaded images can sit at the
      // position the admin chose (including position 0 to become
      // the cover), not at the tail of the list. The dialog also
      // uploads new bytes itself in that case, so [imageFile] is
      // typically `null` here and [imageOrder] is the source of
      // truth for the final list.
      if (imageOrder != null) {
        images
          ..clear()
          ..addAll(imageOrder);
        // Caller-supplied order is authoritative for both the
        // gallery and the cover: an empty [imageOrder] means the
        // admin removed every image and we must clear [imageUrl]
        // too — otherwise we'd leave a stale URL on a product
        // whose gallery is empty.
        imageUrl = images.isNotEmpty ? images.first : '';
      }

      final updatedProduct =
          product.copyWith(imageUrl: imageUrl, images: images);

      // Persist changes to backend and get the updated product.
      final updated = await _productService.updateProduct(
        id,
        updatedProduct,
        removedImageUrls: removedImageUrls,
      );
      final index = _products.indexWhere((p) => p.id == id);
      if (index >= 0) {
        _products[index] = updated;
      }
      _applyAdminFilter();
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
      _applyAdminFilter();
    } catch (e) {
      _error = 'Lỗi xóa sản phẩm: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Quick stock adjust (used by the +/- buttons in product_list_tile)
  // ---------------------------------------------------------------------------

  /// Bump [id]'s stock by [delta] and persist the change.
  ///
  /// Behaviour:
  ///   • The arithmetic stays in the VM: `null` stock is treated
  ///     as "0" and we never let the new value go negative — the
  ///     stepper disables its minus button at the floor, but the VM
  ///     still clamps defensively in case some other caller
  ///     (a unit test, a programmatic widget, a future bulk-edit
  ///     flow) tries to underflow.
  ///   • Persistence goes through
  ///     [IProductService.updateStock] — the dedicated PATCH
  ///     /api/products/{id}/stock endpoint — instead of the full
  ///     PUT. That route rewrites only the stock column, so two
  ///     admins adjusting different products concurrently (or the
  ///     same product's stock vs. description in two tabs) can't
  ///     clobber each other's unrelated edits.
  ///   • Optimistic local update: the row's stock label flips to
  ///     the new value before the network round-trip. On failure
  ///     we revert so the UI stays consistent with the server.
  ///   • Sets [adminSessionExpired] = true on a stale-session 401,
  ///     mirroring [updateProduct]'s contract so the admin shell
  ///     can route the user back to the auth gate.
  Future<int?> quickAdjustStock(String id, int delta) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index < 0) {
      _error = 'Không tìm thấy sản phẩm để điều chỉnh tồn kho';
      notifyListeners();
      return null;
    }
    final current = _products[index];
    final newStock = ((current.stock ?? 0) + delta).clamp(0, 1 << 31);
    // Optimistic: flip the local copy *before* the round-trip so
    // the row's stock number (and the +/- button count) reads the
    // new value the instant the user releases the button. If the
    // PATCH fails we revert via the catch below.
    _products[index] = current.copyWith(stock: newStock);
    _applyAdminFilter();
    notifyListeners();
    try {
      final persisted = await _productService.updateStock(id, newStock);
      // Service layer may have re-shaped the row (e.g. normalised
      // image URLs). Replace the optimistic copy with the server's
      // authoritative version.
      final i = _products.indexWhere((p) => p.id == id);
      if (i >= 0) {
        _products[i] = persisted;
      }
      _applyAdminFilter();
      notifyListeners();
      return persisted.stock;
    } on AdminSessionExpiredException catch (e) {
      // Revert the optimistic local change so the row matches the
      // server. Without this the row would keep the new stock while
      // every other read on the screen uses the cached server
      // version, leading to inconsistent UI after re-auth.
      _products[index] = current;
      _adminSessionExpired = true;
      _error = e.message;
      _applyAdminFilter();
      notifyListeners();
      return null;
    } catch (e) {
      _products[index] = current;
      _error = 'Lỗi cập nhật tồn kho: $e';
      _applyAdminFilter();
      notifyListeners();
      return null;
    }
  }
}