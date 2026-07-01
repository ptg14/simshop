/// Discount mode for an [Event]. Backend matches these exact string
/// values; changing them would silently break validation server-side.
enum DiscountType { percent, fixed }

extension DiscountTypeX on DiscountType {
  String get wire {
    switch (this) {
      case DiscountType.percent:
        return 'percent';
      case DiscountType.fixed:
        return 'fixed';
    }
  }

  String get displayLabel {
    switch (this) {
      case DiscountType.percent:
        return 'Phần trăm';
      case DiscountType.fixed:
        return 'Cố định';
    }
  }

  static DiscountType parse(String? raw) {
    if (raw == 'fixed') return DiscountType.fixed;
    return DiscountType.percent;
  }
}

/// Time-boxed promotion applied to a list of products.
///
/// The backend computes `effective_price` on read; the Flutter side
/// reads it from the product payload (see `Product.effectivePrice`)
/// rather than recomputing, so the admin and customer views always
/// agree on the price.
///
/// `endTime` is stored server-side as unix seconds; here we keep the
/// native `DateTime` to make UI binding trivial.
class Event {
  const Event({
    required this.id,
    this.name = '',
    this.endTime,
    this.discountType = DiscountType.percent,
    this.discountValue = 0,
    this.productIds = const [],
    this.createdAt = 0,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    final end = json['end_time'];
    DateTime? endTime;
    if (end is num) {
      endTime = DateTime.fromMillisecondsSinceEpoch(end.toInt() * 1000,
          isUtc: true);
    }
    final ids = json['product_ids'];
    return Event(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      endTime: endTime,
      discountType: DiscountTypeX.parse(json['discount_type'] as String?),
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      productIds: ids is List
          ? ids.map((e) => e.toString()).toList(growable: false)
          : const [],
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final DateTime? endTime;
  final DiscountType discountType;
  final double discountValue;
  final List<String> productIds;
  final int createdAt;

  /// True iff [endTime] is in the future (or never set). Mirrors the
  /// server's `IsActive` predicate so the admin UI can badge expired
  /// events consistently with how the backend treats them.
  bool isActive([DateTime? now]) {
    if (endTime == null) return true;
    final t = now ?? DateTime.now().toUtc();
    return endTime!.isAfter(t);
  }

  /// Human-readable label for the discount, e.g. `-20%` or `-50.000đ`.
  String formatDiscount() {
    switch (discountType) {
      case DiscountType.percent:
        return '-${discountValue.toStringAsFixed(0)}%';
      case DiscountType.fixed:
        final v = discountValue.toStringAsFixed(0);
        return '-$vđ';
    }
  }

  /// Apply this event to [basePrice]. Mirrors the server's
  /// `Event.ApplyTo` so client-side previews match the eventual
  /// effective price exactly.
  double applyTo(double basePrice) {
    double p;
    switch (discountType) {
      case DiscountType.percent:
        p = basePrice * (1 - discountValue / 100.0);
        break;
      case DiscountType.fixed:
        p = basePrice - discountValue;
        break;
    }
    return p < 0 ? 0 : p;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (endTime != null)
          'end_time': endTime!.toUtc().millisecondsSinceEpoch ~/ 1000,
        'discount_type': discountType.wire,
        'discount_value': discountValue,
        'product_ids': productIds,
        if (createdAt != 0) 'created_at': createdAt,
      };

  Event copyWith({
    String? name,
    DateTime? endTime,
    DiscountType? discountType,
    double? discountValue,
    List<String>? productIds,
  }) =>
      Event(
        id: id,
        name: name ?? this.name,
        endTime: endTime ?? this.endTime,
        discountType: discountType ?? this.discountType,
        discountValue: discountValue ?? this.discountValue,
        productIds: productIds ?? this.productIds,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.id == id &&
          other.name == name &&
          other.endTime == endTime &&
          other.discountType == discountType &&
          other.discountValue == discountValue &&
          _listEq(other.productIds, productIds));

  @override
  int get hashCode => Object.hash(
        id,
        name,
        endTime,
        discountType,
        discountValue,
        Object.hashAll(productIds),
      );
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}