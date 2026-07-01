import 'event.dart';

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
    this.options = const [],
    this.effectivePrice,
    this.currentEvent,
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
        options: json['options'] != null
            ? (json['options'] as List<dynamic>)
                .map((e) => Option.fromJson(e as Map<String, dynamic>))
                .toList()
            : [],
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
        // Backend attaches effective_price + current_event when the
        // product is in an active event. Both default to null on older
        // servers / cache misses — see [effectivePayPrice].
        effectivePrice: (json['effective_price'] as num?)?.toDouble(),
        currentEvent: json['current_event'] != null
            ? Event.fromJson(json['current_event'] as Map<String, dynamic>)
            : null,
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
  final List<Option> options;

  /// Optional store identifier for multi‑store support.
  final String? storeId;
  final double rating;
  // Number of reviews; nullable to handle missing data gracefully.
  final int? reviews;
  // Stock count; nullable to handle missing data gracefully.
  final int? stock;
  final List<String> specs;

  /// Server-computed price after an active event discount. `null`
  /// means no active event applies — render the base price.
  final double? effectivePrice;

  /// The event that produced [effectivePrice]. Lets the UI show a
  /// ribbon ("GIÁ SỰ KIỆN") without re-querying.
  final Event? currentEvent;

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
        'options': options.map((o) => o.toJson()).toList(),
      };

  /// Check if product is on sale (manual [originalPrice] OR active event).
  bool get isOnSale =>
      (originalPrice != null && originalPrice! > price) ||
      currentEvent != null;

  /// Calculate discount percentage.
  int get discountPercentage {
    if (currentEvent != null && price > 0) {
      final eff = effectivePayPrice;
      final saved = price - eff;
      if (saved <= 0) return 0;
      return ((saved / price) * 100).round();
    }
    if (!isOnSale || originalPrice == null) return 0;
    return (((originalPrice! - price) / originalPrice!) * 100).toInt();
  }

  /// Effective price the customer actually pays. When no event is
  /// active or the server didn't decorate this product, this falls
  /// back to the base [price] so UI code never has to null-check.
  double get effectivePayPrice =>
      (effectivePrice != null && effectivePrice! < price)
          ? effectivePrice!
          : price;

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
    List<Option>? options,
    List<String>? categories,
    double? effectivePrice,
    Event? currentEvent,
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
        options: options ?? this.options,
        categories: categories ?? this.categories,
        effectivePrice: effectivePrice ?? this.effectivePrice,
        currentEvent: currentEvent ?? this.currentEvent,
      );
}

class Option {
  Option({required this.id, required this.name, this.imageUrls = const []});

  factory Option.fromJson(Map<String, dynamic> json) => Option(
        id: json['id'] as String,
        name: json['name'] as String,
        imageUrls: json['image_urls'] != null
            ? (json['image_urls'] as List<dynamic>)
                .map((e) => e as String)
                .toList()
            : (json['image_url'] != null ? [json['image_url'] as String] : []),
      );

  final String id;
  final String name;
  final List<String> imageUrls;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'image_urls': imageUrls};
}
