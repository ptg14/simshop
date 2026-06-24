/// Banner slide shown in the home carousel.
///
/// Carries an optional [articleId] — the article that opens when the
/// user taps the slide. The 1-1 article relationship is enforced at
/// the application layer (admin UI), not in the database.
class BannerSlide {
  const BannerSlide({
    required this.id,
    required this.imageUrl,
    this.title = '',
    this.subtitle = '',
    this.ord = 0,
    this.articleId,
  });

  factory BannerSlide.fromJson(Map<String, dynamic> json) => BannerSlide(
        id: json['id'] as String,
        imageUrl: json['image_url'] as String? ?? '',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        ord: (json['ord'] as num?)?.toInt() ?? 0,
        articleId: json['article_id'] as String?,
      );

  final String id;
  final String imageUrl;
  final String title;
  final String subtitle;
  final int ord;
  final String? articleId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'image_url': imageUrl,
        'title': title,
        'subtitle': subtitle,
        'ord': ord,
        'article_id': articleId,
      };

  BannerSlide copyWith({
    String? imageUrl,
    String? title,
    String? subtitle,
    int? ord,
    String? articleId,
    bool clearArticleId = false,
  }) =>
      BannerSlide(
        id: id,
        imageUrl: imageUrl ?? this.imageUrl,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        ord: ord ?? this.ord,
        articleId: clearArticleId ? null : (articleId ?? this.articleId),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BannerSlide &&
          other.id == id &&
          other.imageUrl == imageUrl &&
          other.title == title &&
          other.subtitle == subtitle &&
          other.ord == ord &&
          other.articleId == articleId);

  @override
  int get hashCode => Object.hash(id, imageUrl, title, subtitle, ord, articleId);
}
