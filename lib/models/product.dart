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
    this.categories = const [],
    this.storeId,
    required this.rating,
    this.reviews,
    this.stock,
    required this.specs,
    this.images = const [],
  });

  /// Create a Product from a JSON map.
  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        price: (json['price'] as num).toDouble(),
        originalPrice: json['original_price'] != null
            ? (json['original_price'] as num).toDouble()
            : null,
        imageUrl: json['image_url'] as String? ?? '',
        images: json['images'] != null
            ? (json['images'] as List<dynamic>).map((e) => e as String).toList()
            : (json['image_url'] != null ? [json['image_url'] as String] : []),
        category: json['category'] as String,
        categories: json['categories'] != null
            ? (json['categories'] as List<dynamic>)
                .map((e) => e as String)
                .toList()
            : (json['category'] != null ? [json['category'] as String] : []),
        storeId: json['store_id'] as String?,
        rating: (json['rating'] as num).toDouble(),
        reviews: json['reviews'] as int?,
        stock: json['stock'] as int?,
        specs:
            (json['specs'] as List<dynamic>).map((e) => e as String).toList(),
        // images already populated above
      );
  final String id;
  final String name;
  final String description;
  final double price;
  final double? originalPrice;
  final String imageUrl;
  final String category;
  final List<String> categories;
  final List<String> images;

  /// Optional store identifier for multi‑store support.
  final String? storeId;
  final double rating;
  // Number of reviews; nullable to handle missing data gracefully.
  final int? reviews;
  // Stock count; nullable to handle missing data gracefully.
  final int? stock;
  final List<String> specs;

  /// Convert this Product to a JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'price': price,
        'original_price': originalPrice,
        'image_url': imageUrl,
        'category': category,
        'categories': categories,
        'store_id': storeId,
        'rating': rating,
        'reviews': reviews,
        'stock': stock,
        'specs': specs,
        'images': images,
      };

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
    List<String>? images,
    List<String>? categories,
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
        images: images ?? this.images,
        categories: categories ?? this.categories,
      );
}
