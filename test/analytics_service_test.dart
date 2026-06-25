import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/services/analytics_service.dart';

/// In-memory analytics service for tests so we don't need a real backend.
class _FakeAnalyticsService implements IAnalyticsService {
  final List<({String eventType, String productId})> events = [];
  bool shouldFail = false;
  bool throwOnNetwork = false;

  @override
  Future<void> recordPageview(String eventType, {String productId = ''}) async {
    if (shouldFail) throw Exception('boom');
    events.add((eventType: eventType, productId: productId));
  }
}

void main() {
  group('IAnalyticsService contract', () {
    test('recordPageview(home_view) records an event without a product id', () async {
      final fake = _FakeAnalyticsService();
      await fake.recordPageview('home_view');
      expect(fake.events, hasLength(1));
      expect(fake.events.first.eventType, 'home_view');
      expect(fake.events.first.productId, '');
    });

    test('recordPageview(product_view) records the product id alongside', () async {
      final fake = _FakeAnalyticsService();
      await fake.recordPageview('product_view', productId: 'p-123');
      expect(fake.events, hasLength(1));
      expect(fake.events.first.eventType, 'product_view');
      expect(fake.events.first.productId, 'p-123');
    });

    test('recordPageview swallows nothing — propagates errors', () async {
      final fake = _FakeAnalyticsService()..shouldFail = true;
      expect(
        () => fake.recordPageview('home_view'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
