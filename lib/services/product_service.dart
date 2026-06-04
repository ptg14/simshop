import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../models/product.dart';

/// Response wrapper for paginated product list from backend.
class ProductListResponse {
  final List<Product> products;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  ProductListResponse({
    required this.products,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  factory ProductListResponse.fromJson(Map<String, dynamic> json) =>
      ProductListResponse(
        products: (json['products'] as List<dynamic>)
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        page: json['page'] as int,
        pageSize: json['page_size'] as int,
        totalPages: json['total_pages'] as int,
      );
}

/// Service for fetching products from an API or local storage.
abstract class IProductService {
  Future<List<Product>> getAllProducts();
  Future<List<Product>> getProductsByCategory(String category);
  Future<Product> getProductById(String id);
  Future<List<String>> getCategories();
  Future<List<Product>> searchProducts(String query);

  /// Create a new product and return the created product (with server-generated ID).
  Future<Product> createProduct(Product product);

  /// Update an existing product and return the updated product.
  Future<Product> updateProduct(String id, Product product);

  /// Delete a product by its identifier.
  Future<void> deleteProduct(String id);

  /// Upload an image file and return the image URL.
  Future<String> uploadImage(File file);
}

/// Real implementation that talks to the Go backend API.
class RealProductService implements IProductService {
  // Base URL of the backend. Adjust if the backend runs on a different host/port.
  final String _baseUrl;

  RealProductService({String? baseUrl})
      : _baseUrl = baseUrl ?? 'http://localhost:8080';

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
  Product _resolveProductImages(Product product) {
    return product.copyWith(imageUrl: _resolveImageUrl(product.imageUrl));
  }

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

  @override
  Future<List<String>> getCategories() async {
    final products = await getAllProducts();
    return products.map((p) => p.category).toSet().toList();
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
    final response = await http.delete(_productUri(id));
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete product $id: ${response.statusCode}');
    }
  }

  @override
  Future<Product> createProduct(Product product) async {
    final response = await http.post(
      _productsUri(),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(product.toJson()),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      final body = response.body.isNotEmpty ? response.body : 'Unknown error';
      throw Exception('Failed to create product: $body');
    }
    return _resolveProductImages(
      Product.fromJson(json.decode(response.body) as Map<String, dynamic>),
    );
  }

  @override
  Future<Product> updateProduct(String id, Product product) async {
    final response = await http.put(
      _productUri(id),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(product.toJson()),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      final body = response.body.isNotEmpty ? response.body : 'Unknown error';
      throw Exception('Failed to update product $id: $body');
    }
    return _resolveProductImages(
      Product.fromJson(json.decode(response.body) as Map<String, dynamic>),
    );
  }

  @override
  Future<String> uploadImage(File file) async {
    final request = http.MultipartRequest('POST', _uploadUri());
    request.files.add(await http.MultipartFile.fromPath('image', file.path));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw Exception('Failed to upload image: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    return data['image_url'] as String;
  }
}
