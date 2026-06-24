/// Article attached to a banner slide.
///
/// Slice 1 uses only [id], [title], and [body]. Slice 3 adds
/// [coverImageUrl] and [productIds] for the full CRUD form.
class Article {
  const Article({
    required this.id,
    required this.title,
    this.body = '',
    this.coverImageUrl = '',
    this.productIds = const [],
  });

  factory Article.fromJson(Map<String, dynamic> json) => Article(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? json['body_markdown'] as String? ?? '',
        coverImageUrl: json['cover_image_url'] as String? ?? '',
        productIds: ((json['product_ids'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
      );

  final String id;
  final String title;
  final String body;
  final String coverImageUrl;
  final List<String> productIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        // Server (Go models.Article) tags this field `body_markdown`.
        // Sending `body` makes the strict JSON decoder in the handler
        // reject the request with 400 "unknown field".
        'body_markdown': body,
        'cover_image_url': coverImageUrl,
        'product_ids': productIds,
      };

  Article copyWith({
    String? title,
    String? body,
    String? coverImageUrl,
    List<String>? productIds,
  }) =>
      Article(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        coverImageUrl: coverImageUrl ?? this.coverImageUrl,
        productIds: productIds ?? this.productIds,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Article &&
          other.id == id &&
          other.title == title &&
          other.body == body &&
          other.coverImageUrl == coverImageUrl &&
          _listEq(other.productIds, productIds));

  @override
  int get hashCode =>
      Object.hash(id, title, body, coverImageUrl, Object.hashAll(productIds));

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
