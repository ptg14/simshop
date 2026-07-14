import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../models/category.dart';
import '../models/product.dart';
import '_http_with_admin_token.dart';
import 'admin_auth_service.dart';
import 'i_product_service.dart';
import 'product_list_response.dart';

// Re-export so existing callers that import
// `package:simshop/services/product_service.dart` and reference
// `IProductService` / `ProductListResponse` keep working. The
// concrete definitions live in the dedicated files; this is a
// facade for the service layer's public API.
export 'i_product_service.dart';
export 'product_list_response.dart';

/// Real implementation that talks to the Go backend API.
class RealProductService implements IProductService {

  RealProductService({String? baseUrl, IAdminAuthService? authService})
      : _baseUrl = baseUrl ?? ApiConfig.apiBaseUrl,
        _auth = authService;
  // Base URL of the backend. Adjust if the backend runs on a different host/port.
  final String _baseUrl;
  // Optional auth service — when present, admin write endpoints attach
  // `Authorization: Bearer <token>`. Optional so unit tests can
  // construct the service without a SharedPreferences dependency.
  final IAdminAuthService? _auth;

  Uri _productsUri() => Uri.parse('$_baseUrl/api/products');
  Uri _productUri(String id) => Uri.parse('$_baseUrl/api/products/$id');
  Uri _uploadUri() => Uri.parse('$_baseUrl/api/upload');

  /// Convert a relative image URL (e.g. "/uploads/abc.jpg") to an absolute URL.
  String _resolveImageUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/')) {
      return '$_baseUrl$url';
    }
    return url;
  }

  /// Apply image URL resolution to a single product.
  Product _resolveProductImages(Product product) => product.copyWith(imageUrl: _resolveImageUrl(product.imageUrl));

  /// Build a products URI with optional query parameters.
  Uri _filteredProductsUri({
    String? category,
    String? search,
    double? minPrice,
    double? maxPrice,
    double? minRating,
    String? storeId,
    String? sortBy,
    int? page,
    int? pageSize,
  }) {
    final params = <String, String>{};
    if (category != null && category.isNotEmpty) params['category'] = category;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (minPrice != null) params['min_price'] = minPrice.toString();
    if (maxPrice != null) params['max_price'] = maxPrice.toString();
    if (minRating != null) params['min_rating'] = minRating.toString();
    if (storeId != null && storeId.isNotEmpty) params['store_id'] = storeId;
    if (sortBy != null && sortBy.isNotEmpty) params['sort_by'] = sortBy;
    if (page != null) params['page'] = page.toString();
    if (pageSize != null) params['page_size'] = pageSize.toString();
    return Uri.parse('$_baseUrl/api/products')
        .replace(queryParameters: params.isNotEmpty ? params : null);
  }

  @override
  Future<List<Product>> getAllProducts() async {
    final response = await http.get(_productsUri());
    if (response.statusCode != 200) {
      throw Exception('Failed to load products: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    return ProductListResponse.fromJson(data)
        .products
        .map(_resolveProductImages)
        .toList();
  }

  @override
  Future<List<Product>> getProductsByCategory(String category) async {
    final uri = _filteredProductsUri(category: category);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load products: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    return ProductListResponse.fromJson(data)
        .products
        .map(_resolveProductImages)
        .toList();
  }

  @override
  Future<Product> getProductById(String id) async {
    final response = await http.get(_productUri(id));
    if (response.statusCode != 200) {
      throw Exception('Product not found: $id');
    }
    return _resolveProductImages(
      Product.fromJson(json.decode(response.body) as Map<String, dynamic>),
    );
  }

  /// Delete a sub-category via backend. Used by the admin Categories tab.
  @override
  Future<void> deleteCategory(String name) async {
    final uri =
        Uri.parse('$_baseUrl/api/categories/${Uri.encodeComponent(name)}');
    final response = await http.delete(uri,
        headers: await withAdminAuth(_auth, const {}));
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete category: ${response.statusCode}');
    }
  }

  @override
  Future<List<String>> getLargeCategories() async {
    final uri = Uri.parse('$_baseUrl/api/large-categories');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to load large categories: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['large_categories'] == null) return const [];
    return (data['large_categories'] as List<dynamic>)
        .map((e) => e as String)
        .toList();
  }

  @override
  Future<List<Category>> getCategoriesWithParent() async {
    final uri = Uri.parse('$_baseUrl/api/categories/with-parent');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to load categories with parent: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['categories'] == null) return const [];
    return (data['categories'] as List<dynamic>)
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createLargeCategory(String name) async {
    final uri = Uri.parse('$_baseUrl/api/large-categories');
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final response = await http.post(uri,
        headers: headers,
        body: json.encode({'name': name}));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to create large category: ${response.statusCode}');
    }
  }

  @override
  Future<void> deleteLargeCategory(String name) async {
    final uri = Uri.parse(
        '$_baseUrl/api/large-categories/${Uri.encodeComponent(name)}');
    final response = await http.delete(uri,
        headers: await withAdminAuth(_auth, const {}));
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete large category: ${response.statusCode}');
    }
  }

  @override
  Future<void> createCategoryWithParent(
      String name, String largeCategoryName) async {
    final uri = Uri.parse('$_baseUrl/api/categories');
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final response = await http.post(uri,
        headers: headers,
        body: json.encode({
          'name': name,
          'large_category': largeCategoryName,
        }));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(
          'Failed to create category with parent: ${response.statusCode}');
    }
  }

  @override
  Future<List<Product>> searchProducts(String query) async {
    final uri = _filteredProductsUri(search: query);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Search failed: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    return ProductListResponse.fromJson(data)
        .products
        .map(_resolveProductImages)
        .toList();
  }

  @override
  Future<void> deleteProduct(String id) async {
    final response = await http.delete(_productUri(id),
        headers: await withAdminAuth(_auth, const {}));
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete product $id: ${response.statusCode}');
    }
  }

  @override
  Future<Product> createProduct(Product product, {List<String>? removedImageUrls}) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final body = _encodeProductBody(product, removedImageUrls: removedImageUrls);
    final response = await http.post(_productsUri(), headers: headers, body: body);
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 201 && response.statusCode != 200) {
      final body = response.body.isNotEmpty ? response.body : 'Unknown error';
      throw Exception('Failed to create product: $body');
    }
    return _resolveProductImages(
      Product.fromJson(json.decode(response.body) as Map<String, dynamic>),
    );
  }

  @override
  Future<Product> updateProduct(String id, Product product, {List<String>? removedImageUrls}) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final body = _encodeProductBody(product, removedImageUrls: removedImageUrls);
    final response = await http.put(_productUri(id), headers: headers, body: body);
    // Detect a stale cached token (server restart, TTL elapsed, etc.)
    // and surface a typed exception so the UI can route the user
    // back to AdminAuthGate. Done before the generic status check so
    // the message is unambiguous.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 200 && response.statusCode != 204) {
      final body = response.body.isNotEmpty ? response.body : 'Unknown error';
      throw Exception('Failed to update product $id: $body');
    }
    return _resolveProductImages(
      Product.fromJson(json.decode(response.body) as Map<String, dynamic>),
    );
  }

  /// Serialize a product for the create/update endpoints, optionally
  /// attaching the [removed_image_urls] field the admin dialog uses to
  /// track images the user unchecked in the gallery. Keeping this in a
  /// helper lets create/update share identical body assembly logic.
  String _encodeProductBody(
    Product product, {
    List<String>? removedImageUrls,
  }) {
    final map = product.toJson();
    if (removedImageUrls != null && removedImageUrls.isNotEmpty) {
      map['removed_image_urls'] = removedImageUrls;
    }
    return json.encode(map);
  }

  @override
  Future<String?> uploadImage(
    dynamic file, {
    String? productName,
    String? productId,
    int startIndex = 1,
  }) async {
    final request = http.MultipartRequest('POST', _uploadUri());
    _applyNamingContext(request, productName, productId, startIndex);
    await attachAdminAuth(_auth, request);

    if (file is File) {
      request.files.add(await http.MultipartFile.fromPath('image', file.path));
    } else if (file is XFile) {
      final bytes = await file.readAsBytes();
      final multipart =
          http.MultipartFile.fromBytes('image', bytes, filename: file.name);
      request.files.add(multipart);
    } else if (file is Uint8List) {
      final multipart =
          http.MultipartFile.fromBytes('image', file, filename: 'upload.jpg');
      request.files.add(multipart);
    } else {
      throw Exception('Unsupported image type for upload');
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    // Detect a stale cached token (server restart, TTL elapsed, etc.)
    // and surface a typed exception so the UI can route the user
    // back to AdminAuthGate. Done before the generic status check
    // so the message is unambiguous. Without this, the dead token
    // stays in SharedPreferences and the user can't recover without
    // manually clearing app data.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 200) {
      throw Exception('Failed to upload image: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    // Prefer image_urls array if present
    if (data['image_urls'] != null) {
      final list = (data['image_urls'] as List<dynamic>)
          .map((e) => e as String)
          .toList();
      return list.isNotEmpty ? list[0] : (data['image_url'] as String);
    }
    return data['image_url'] as String;
  }

  /// Upload multiple images and return their URLs in order.
  @override
  Future<List<String>> uploadImages(
    List<dynamic> files, {
    String? productName,
    String? productId,
    int startIndex = 1,
  }) async {
    final request = http.MultipartRequest('POST', _uploadUri());
    _applyNamingContext(request, productName, productId, startIndex);
    await attachAdminAuth(_auth, request);
    for (final file in files) {
      if (file is File) {
        request.files
            .add(await http.MultipartFile.fromPath('images', file.path));
      } else if (file is XFile) {
        final bytes = await file.readAsBytes();
        final multipart =
            http.MultipartFile.fromBytes('images', bytes, filename: file.name);
        request.files.add(multipart);
      } else if (file is Uint8List) {
        final multipart = http.MultipartFile.fromBytes('images', file,
            filename: 'upload.jpg');
        request.files.add(multipart);
      } else {
        throw Exception('Unsupported image type for upload');
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    // Mirror uploadImage: clear the dead token on a stale-session
    // 401 so the admin can re-authenticate via AdminAuthGate.
    // Without this, the second, third, ... uploads all hit the
    // same dead credential and surface a generic "Failed to upload
    // images: 401" with no path back to the auth gate.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 200) {
      throw Exception('Failed to upload images: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (data['image_urls'] != null) {
      return (data['image_urls'] as List<dynamic>)
          .map((e) => e as String)
          .toList();
    }
    // Fallback to single image_url
    return [data['image_url'] as String];
  }

  /// Attach naming context fields to a multipart request. Backend uses
  /// these to build `YYYYMMDD-<slug>-<index>.<ext>` filenames.
  void _applyNamingContext(
    http.MultipartRequest request,
    String? productName,
    String? productId,
    int startIndex,
  ) {
    if (productName != null && productName.trim().isNotEmpty) {
      request.fields['product_name'] = productName.trim();
    }
    if (productId != null && productId.trim().isNotEmpty) {
      request.fields['product_id'] = productId.trim();
    }
    if (startIndex > 0) {
      request.fields['index'] = startIndex.toString();
    }
  }
}
