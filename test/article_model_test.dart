import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/article.dart';

/// Bug: PUT /api/articles/<id> failed with 400
///   {"error":"invalid request body: json: unknown field \"body\""}
///
/// Root cause: client `Article.toJson()` wrote the body under the
/// key `"body"`, but the Go backend's models.Article JSON tag is
/// `"body_markdown"`. Same shape mismatch exists for incoming
/// `Article.fromJson` which only reads `body` first and falls back
/// to `body_markdown` — the server never sends `body` so the body
/// silently became empty on round-trip.
///
/// These tests pin the *wire* contract to the Go server's field
/// names: `body_markdown`, `cover_image_url`, `product_ids`. Any
/// future drift fails the test before hitting production.
void main() {
  group('Article.toJson', () {
    test('serializes body under body_markdown (matches Go server tag)', () {
      const a = Article(
        id: 'a-1',
        title: 'Hello',
        body: '## Body',
        coverImageUrl: 'https://example.test/c.jpg',
        productIds: ['p-1', 'p-2'],
      );
      final json = a.toJson();

      // Body must be sent as body_markdown so the Go handler's
      // DisallowUnknownFields doesn't 400.
      expect(json.containsKey('body'), isFalse,
          reason: 'client must not send "body" — Go server rejects it');
      expect(json['body_markdown'], '## Body');

      // Other fields must align with the Go struct tags too.
      expect(json['id'], 'a-1');
      expect(json['title'], 'Hello');
      expect(json['cover_image_url'], 'https://example.test/c.jpg');
      expect(json['product_ids'], ['p-1', 'p-2']);
    });
  });

  group('Article.fromJson', () {
    test('reads body_markdown from the Go server response', () {
      // Simulate the exact payload the Go server returns.
      final a = Article.fromJson({
        'id': 'a-1',
        'title': 'Hello',
        'body_markdown': '## Body',
        'cover_image_url': 'https://example.test/c.jpg',
        'product_ids': ['p-1'],
        'created_at': 0,
      });
      expect(a.id, 'a-1');
      expect(a.title, 'Hello');
      expect(a.body, '## Body',
          reason: 'must decode body_markdown — server uses that field');
      expect(a.coverImageUrl, 'https://example.test/c.jpg');
      expect(a.productIds, ['p-1']);
    });
  });
}
