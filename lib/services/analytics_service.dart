import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
}

class RealAnalyticsService implements IAnalyticsService {
  RealAnalyticsService({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? 'http://localhost:8080',
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Uri _pageviewUri() => Uri.parse('$_baseUrl/api/analytics/pageview');

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
}
