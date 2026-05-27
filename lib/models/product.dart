/// Represents a product in the store.
class Product {
  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.originalPrice,
    required this.imageUrl,
    required this.category,
    this.storeId,
    required this.rating,
    this.reviews,
    this.stock,
    required this.specs,
  });
  final String id;
  final String name;
  final String description;
  final double price;
  final double? originalPrice;
  final String imageUrl;
  final String category;

  /// Optional store identifier for multi‑store support.
  final String? storeId;
  final double rating;
  // Number of reviews; nullable to handle missing data gracefully.
  final int? reviews;
  // Stock count; nullable to handle missing data gracefully.
  final int? stock;
  final List<String> specs;

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
    String? storeId,
    double? rating,
    int? reviews,
    int? stock,
    List<String>? specs,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        originalPrice: originalPrice ?? this.originalPrice,
        imageUrl: imageUrl ?? this.imageUrl,
        category: category ?? this.category,
        storeId: storeId ?? this.storeId,
        rating: rating ?? this.rating,
        reviews: reviews ?? this.reviews,
        stock: stock ?? this.stock,
        specs: specs ?? this.specs,
      );
}
