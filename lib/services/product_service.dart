// Added CRUD methods: createProduct, updateProduct for full backend integration.
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/product.dart';

/// Service for fetching products from an API or local storage.
abstract class IProductService {
  Future<List<Product>> getAllProducts();
  Future<List<Product>> getProductsByCategory(String category);
  Future<Product> getProductById(String id);
  Future<List<String>> getCategories();
  Future<List<Product>> searchProducts(String query);

  /// Create a new product.
  Future<void> createProduct(Product product);

  /// Update an existing product.
  Future<void> updateProduct(String id, Product product);

  /// Delete a product by its identifier.
  Future<void> deleteProduct(String id);
}

/// Real implementation that talks to the Go backend API.
class RealProductService implements IProductService {
  // Base URL of the backend. Adjust if the backend runs on a different host/port.
  final String _baseUrl;

  RealProductService({String? baseUrl})
      : _baseUrl = baseUrl ?? 'http://localhost:8080';

  Uri _productsUri() => Uri.parse('$_baseUrl/api/products');
  Uri _productUri(String id) => Uri.parse('$_baseUrl/api/products/$id');

  @override
  Future<List<Product>> getAllProducts() async {
    final response = await http.get(_productsUri());
    if (response.statusCode != 200) {
      throw Exception('Failed to load products: ${response.statusCode}');
    }
    final List<dynamic> data = json.decode(response.body) as List<dynamic>;
    return data
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Product>> getProductsByCategory(String category) async {
    final all = await getAllProducts();
    return all.where((p) => p.category == category).toList();
  }

  @override
  Future<Product> getProductById(String id) async {
    final response = await http.get(_productUri(id));
    if (response.statusCode != 200) {
      throw Exception('Product not found: $id');
    }
    return Product.fromJson(json.decode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<List<String>> getCategories() async {
    final products = await getAllProducts();
    return products.map((p) => p.category).toSet().toList();
  }

  @override
  Future<List<Product>> searchProducts(String query) async {
    final all = await getAllProducts();
    final lower = query.toLowerCase();
    return all
        .where((p) =>
            p.name.toLowerCase().contains(lower) ||
            p.description.toLowerCase().contains(lower))
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
  Future<void> createProduct(Product product) async {
    final response = await http.post(
      _productsUri(),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(product.toJson()),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to create product: ${response.statusCode}');
    }
  }

  @override
  Future<void> updateProduct(String id, Product product) async {
    final response = await http.put(
      _productUri(id),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(product.toJson()),
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to update product $id: ${response.statusCode}');
    }
  }
}

// Mock implementation removed. Frontend now exclusively uses the real backend API via RealProductService.
