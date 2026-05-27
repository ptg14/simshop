import '../models/product.dart';

/// Service for fetching products from an API or local storage.
abstract class IProductService {
  Future<List<Product>> getAllProducts();
  Future<List<Product>> getProductsByCategory(String category);
  Future<Product> getProductById(String id);
  Future<List<String>> getCategories();
  Future<List<Product>> searchProducts(String query);
}

/// Mock implementation of product service.
class MockProductService implements IProductService {
  final List<Product> _mockProducts = [
    Product(
      id: '1',
      name: 'PC TTG GAMING IJ12405',
      description: 'High-performance gaming PC with latest specs',
      price: 23480000,
      originalPrice: 28000000,
      imageUrl: 'https://via.placeholder.com/300x300?text=PC+Gaming+1',
      category: 'PC Gaming',
      rating: 4.8,
      reviews: 156,
      stock: 12,
      specs: ['Intel i9-13900K', 'RTX 4080', '32GB RAM', '2TB SSD'],
      storeId: 'store1',
    ),
    Product(
      id: '2',
      name: 'PC AMG GAMING Ryzen 7',
      description: 'Excellent gaming PC with AMD processor',
      price: 15990000,
      originalPrice: 18500000,
      imageUrl: 'https://via.placeholder.com/300x300?text=PC+Gaming+2',
      category: 'PC Gaming',
      rating: 4.6,
      reviews: 98,
      stock: 8,
      specs: ['Ryzen 7 7700X', 'RTX 4070', '16GB RAM', '1TB SSD'],
      storeId: 'store2',
    ),
    Product(
      id: '3',
      name: 'PC TTG GAMING IJ24405',
      description: 'Budget-friendly gaming PC',
      price: 19800000,
      originalPrice: 23500000,
      imageUrl: 'https://via.placeholder.com/300x300?text=PC+Gaming+3',
      category: 'PC Gaming',
      rating: 4.5,
      reviews: 87,
      stock: 15,
      specs: ['Intel i7-13700K', 'RTX 4070 Ti', '32GB RAM', '1TB SSD'],
      storeId: 'store1',
    ),
    Product(
      id: '4',
      name: 'PC HIGH PERFORMANCE',
      description: 'Ultimate gaming machine',
      price: 45800000,
      imageUrl: 'https://via.placeholder.com/300x300?text=PC+Gaming+4',
      category: 'PC Gaming',
      rating: 4.9,
      reviews: 234,
      stock: 5,
      specs: ['Intel i9-13900KS', 'RTX 4090', '64GB RAM', '4TB SSD'],
      storeId: 'store2',
    ),
    Product(
      id: '5',
      name: 'PC TTG DESIGNER IJ24405',
      description: 'Perfect for design and content creation',
      price: 38500000,
      imageUrl: 'https://via.placeholder.com/300x300?text=PC+Design+1',
      category: 'PC Design',
      rating: 4.7,
      reviews: 102,
      stock: 10,
      specs: ['Intel i9-13900K', 'RTX 4080 Super', '32GB RAM', '2TB SSD'],
      storeId: 'store1',
    ),
    Product(
      id: '6',
      name: 'PC CHO GAME HIỆU SUẤT',
      description: 'Performance-focused gaming PC',
      price: 22800000,
      originalPrice: 25000000,
      imageUrl: 'https://via.placeholder.com/300x300?text=PC+Gaming+5',
      category: 'PC Gaming',
      rating: 4.4,
      reviews: 76,
      stock: 20,
      specs: ['Ryzen 9 7950X', 'RTX 4070 Ti', '16GB RAM', '1TB SSD'],
      storeId: 'store2',
    ),
    Product(
      id: '7',
      name: 'Gaming Monitor RTX 240Hz',
      description: 'High refresh rate gaming monitor',
      price: 8900000,
      imageUrl: 'https://via.placeholder.com/300x300?text=Monitor+1',
      category: 'PC Accessories',
      rating: 4.6,
      reviews: 54,
      stock: 25,
      specs: ['27 inch', '240Hz', '1ms', 'IPS Panel'],
      storeId: 'store1',
    ),
    Product(
      id: '8',
      name: 'RGB Gaming Keyboard',
      description: 'Mechanical gaming keyboard with RGB',
      price: 2500000,
      originalPrice: 3200000,
      imageUrl: 'https://via.placeholder.com/300x300?text=Keyboard+1',
      category: 'PC Accessories',
      rating: 4.5,
      reviews: 120,
      stock: 50,
      specs: ['Mechanical Switches', 'RGB Lighting', 'Wired'],
      storeId: 'store2',
    ),
  ];

  @override
  Future<List<Product>> getAllProducts() async {
    // Removed artificial delay to avoid pending timers in widget tests.
    return _mockProducts;
  }

  @override
  Future<List<Product>> getProductsByCategory(String category) async {
    return _mockProducts
        .where((product) => product.category == category)
        .toList();
  }

  @override
  Future<Product> getProductById(String id) async {
    return _mockProducts.firstWhere((product) => product.id == id);
  }

  @override
  Future<List<String>> getCategories() async {
    return _mockProducts.map((product) => product.category).toSet().toList();
  }

  @override
  Future<List<Product>> searchProducts(String query) async {
    final lowerQuery = query.toLowerCase();
    return _mockProducts
        .where((product) =>
            product.name.toLowerCase().contains(lowerQuery) ||
            product.description.toLowerCase().contains(lowerQuery))
        .toList();
  }
}
