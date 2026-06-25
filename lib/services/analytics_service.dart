import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// One row in the admin overview's "most-viewed products" table.
class TopProductView {
  const TopProductView({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.viewCount,
  });

  final String productId;
  final String name;
  final String imageUrl;
  final int viewCount;

  factory TopProductView.fromJson(Map<String, dynamic> json) => TopProductView(
        productId: json['product_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        imageUrl: json['image_url'] as String? ?? '',
        viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      );
}

/// Aggregate pageview summary returned by the admin endpoint.
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalVisits,
    required this.topProducts,
  });

  final int totalVisits;
  final List<TopProductView> topProducts;

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['top_products'] as List<dynamic>? ?? const [];
    return AnalyticsSummary(
      totalVisits: (json['total_visits'] as num?)?.toInt() ?? 0,
      topProducts: raw
          .map((e) => TopProductView.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Pageview + summary tracking for the admin overview.
///
/// Mirrors the IStoreService pattern: small interface, real HTTP
/// implementation. The service is intentionally fire-and-forget — every
/// method must be safe to call from `initState` without blocking
/// navigation. Errors are swallowed because tracking is not critical
/// to the user-facing flow; if the backend is down, the app still
/// renders.
abstract class IAnalyticsService {
  /// Record one pageview event. [eventType] is one of
  /// `home_view` / `product_view` (whitelisted by the backend).
  /// [productId] is optional — empty for `home_view`.
  Future<void> recordPageview(String eventType, {String productId = ''});

  /// Fetch the admin summary: total visits + top-N most-viewed products.
  /// Returns an empty [AnalyticsSummary] on any failure (the admin UI
  /// then renders zeros + an empty list, not a crash).
  Future<AnalyticsSummary> getSummary({int topN = 5});
}

class RealAnalyticsService implements IAnalyticsService {
  RealAnalyticsService({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? 'http://localhost:8080',
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Uri _pageviewUri() => Uri.parse('$_baseUrl/api/analytics/pageview');
  Uri _summaryUri(int topN) =>
      Uri.parse('$_baseUrl/api/admin/analytics/summary?limit=$topN');

  @override
  Future<void> recordPageview(String eventType, {String productId = ''}) async {
    // Fire-and-forget: don't block the caller (initState) on a network
    // round trip. We deliberately don't await this in the widget.
    try {
      final body = <String, dynamic>{'event_type': eventType};
      if (productId.isNotEmpty) body['product_id'] = productId;
      await _client.post(
        _pageviewUri(),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
    } catch (_) {
      // Tracking failure must never crash the UI.
    }
  }

  @override
  Future<AnalyticsSummary> getSummary({int topN = 5}) async {
    try {
      final response = await _client.get(_summaryUri(topN));
      if (response.statusCode != 200) {
        return const AnalyticsSummary(totalVisits: 0, topProducts: []);
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      return AnalyticsSummary.fromJson(data);
    } catch (_) {
      // Admin UI shows zeros on failure rather than crashing.
      return const AnalyticsSummary(totalVisits: 0, topProducts: []);
    }
  }
}
