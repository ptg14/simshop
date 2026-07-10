import '../models/product.dart';

/// Response wrapper for paginated product list from backend.
class ProductListResponse {

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
  final List<Product> products;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;
}
