/// Represents a product in the store.
class Product {
  final String id;
  final String name;
  final String description;
  final double price;
  final double? originalPrice;
  final String imageUrl;
  final String category;
  final double rating;
  final int reviews;
  final int stock;
  final List<String> specs;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.originalPrice,
    required this.imageUrl,
    required this.category,
    required this.rating,
    required this.reviews,
    required this.stock,
    required this.specs,
  });

  /// Check if product is on sale.
  bool get isOnSale => originalPrice != null && originalPrice! > price;

  /// Calculate discount percentage.
  int get discountPercentage {
    if (!isOnSale) return 0;
    return (((originalPrice! - price) / originalPrice!) * 100).toInt();
  }

  /// Create a copy with modified fields.
  Product copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    double? originalPrice,
    String? imageUrl,
    String? category,
    double? rating,
    int? reviews,
    int? stock,
    List<String>? specs,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      reviews: reviews ?? this.reviews,
      stock: stock ?? this.stock,
      specs: specs ?? this.specs,
    );
  }
}
