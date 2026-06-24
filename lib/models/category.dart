/// A "Large" / parent category that groups sub-categories.
///
/// Example: "Clothing" is a Large category that contains sub-categories like
/// "Shirts" and "Pants".
class LargeCategory {
  LargeCategory({required this.name});

  /// Create a [LargeCategory] from a JSON map (backend `large_categories`).
  factory LargeCategory.fromJson(Map<String, dynamic> json) =>
      LargeCategory(name: json['name'] as String);

  final String name;

  Map<String, dynamic> toJson() => {'name': name};

  @override
  bool operator ==(Object other) =>
      other is LargeCategory && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// A sub-category, optionally linked to a [LargeCategory] (parent).
///
/// When [largeCategory] is `null` the sub-category has no parent (orphan,
/// typically the result of deleting a parent Large category).
class Category {
  Category({required this.name, this.largeCategory});

  /// Create a [Category] from a JSON map produced by
  /// `GET /api/categories/with-parent`:
  /// `{"name": "Shirts", "large_category": "Clothing"}`.
  factory Category.fromJson(Map<String, dynamic> json) => Category(
        name: json['name'] as String,
        largeCategory: json['large_category'] as String?,
      );

  final String name;

  /// Name of the parent Large category, or `null` if unassigned.
  final String? largeCategory;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (largeCategory != null) 'large_category': largeCategory,
      };

  @override
  bool operator ==(Object other) =>
      other is Category &&
      other.name == name &&
      other.largeCategory == largeCategory;

  @override
  int get hashCode => Object.hash(name, largeCategory);
}
