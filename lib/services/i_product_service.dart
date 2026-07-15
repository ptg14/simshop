import '../models/category.dart';
import '../models/product.dart';

/// Service for fetching products from an API or local storage.
abstract class IProductService {
  Future<List<Product>> getAllProducts();
  Future<List<Product>> getProductsByCategory(String category);
  Future<Product> getProductById(String id);
  Future<List<Product>> searchProducts(String query);
  /// Delete a sub-category by name. Used by the admin "Categories" tab.
  Future<void> deleteCategory(String name);

  // ---- Large / parent categories ----
  /// Fetch the list of "Large" (parent) category names.
  Future<List<String>> getLargeCategories();

  /// Fetch every sub-category together with its parent Large category name.
  Future<List<Category>> getCategoriesWithParent();

  /// Persist a new Large category.
  Future<void> createLargeCategory(String name);

  /// Delete a Large category. Subs become orphan (`largeCategory == null`).
  Future<void> deleteLargeCategory(String name);

  /// Persist a new sub-category and link it to the given Large category.
  /// If [largeCategoryName] does not exist, the backend will create it.
  Future<void> createCategoryWithParent(String name, String largeCategoryName);

  /// Create a new product and return the created product (with server-generated ID).
  ///
  /// [removedImageUrls] is accepted for symmetry with [updateProduct] but
  /// is always a no-op on the create path: a brand-new product has no
  /// pre-existing images to remove.
  Future<Product> createProduct(Product product, {List<String>? removedImageUrls});

  /// Update an existing product and return the updated product.
  ///
  /// [removedImageUrls] lists image URLs the admin dropped from the
  /// gallery. The backend best-effort deletes the underlying files
  /// after the DB UPDATE commits, so /uploads/ doesn't accumulate
  /// orphans. Pass `null` or an empty list to keep current behavior.
  Future<Product> updateProduct(String id, Product product, {List<String>? removedImageUrls});

  /// Rewrite ONLY the stock column for [id]. The quick-adjust
  /// stepper on the admin product list uses this so a ±1 nudge
  /// doesn't have to PUT the entire product back to the backend
  /// (which would risk a clobber if another admin tab edited the
  /// same row in the meantime).
  ///
  /// [stock] is nullable: pass `null` to clear (= unknown, the
  /// frontend renders as "?"). Negative integers are rejected at
  /// the backend (400).
  ///
  /// Returns the freshly-refetched product so the caller doesn't
  /// need a follow-up GET. Throws if the product id doesn't exist
  /// (the service surfaces 404 → `StateError`-like exception; the
  /// VM maps it to `AdminSessionExpiredException` for 401s).
  Future<Product> updateStock(String id, int? stock);

  /// Delete a product by its identifier.
  Future<void> deleteProduct(String id);

  /// Upload an image file and return the image URL.
  ///
  /// [productName] / [productId] / [startIndex] are forwarded to the
  /// backend as multipart form fields so the server can build a
  /// descriptive filename (YYYYMMDD-<slug>-<index>.<ext>).
  Future<String?> uploadImage(
    dynamic file, {
    String? productName,
    String? productId,
    int startIndex = 1,
  });

  /// Upload multiple images and return their URLs in order.
  ///
  /// See [uploadImage] for the meaning of [productName] / [productId] /
  /// [startIndex]; per-file ordinals run from [startIndex] upward.
  Future<List<String>> uploadImages(
    List<dynamic> files, {
    String? productName,
    String? productId,
    int startIndex = 1,
  });
}
