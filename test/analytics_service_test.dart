import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/services/analytics_service.dart';
import 'support/backend_check.dart';

/// Integration test for [RealAnalyticsService] — hits the real Go
/// backend at localhost:8080 (started via `cd backend && go run`).
/// Skipped automatically if the backend is not reachable.
///
/// Requires seed data so the top_products JOIN has rows to aggregate.
/// Run `cd backend && go run ./cmd/seed/main.go` once before this
/// test to populate the products table.
void main() {
  group('RealAnalyticsService (integration)', () {
    setUpAll(() async {
      await skipIfBackendDown();
    });

    test('recordPageview posts to /api/analytics/pageview and increments '
        'total_visits in /api/admin/analytics/summary', () async {
      final service = RealAnalyticsService();

      // Snapshot total visits BEFORE firing.
      final before = await service.getSummary(topN: 1);

      // Use a product id guaranteed to exist (p1 is seeded by
      // ./cmd/seed). If seed hasn't run, this product_id won't be
      // found in the JOIN but the pageview row is still recorded.
      await service.recordPageview('product_view', productId: 'p1');

      // Snapshot after. Total must grow by 1.
      final after = await service.getSummary(topN: 5);

      expect(after.totalVisits, before.totalVisits + 1,
          reason: 'total_visits should increase by exactly 1 after '
              'a single POST /api/analytics/pageview');
    });

    test('getSummary returns the top products sorted by view_count DESC',
        () async {
      final service = RealAnalyticsService();

      // Fire 3 pageviews for p1 and 1 for p2 — p1 should rank first.
      await service.recordPageview('product_view', productId: 'p1');
      await service.recordPageview('product_view', productId: 'p1');
      await service.recordPageview('product_view', productId: 'p1');
      await service.recordPageview('product_view', productId: 'p2');

      final summary = await service.getSummary(topN: 5);

      // The product p1 must be at the top with at least 3 views.
      // (Other tests in the suite may have added more; we only assert
      //  the ordering invariant, not exact counts.)
      expect(summary.topProducts, isNotEmpty);
      expect(summary.topProducts.first.productId, 'p1',
          reason: 'p1 had 3 views just now, must be #1');
      expect(summary.topProducts.first.viewCount, greaterThanOrEqualTo(3));
    });
  });
}
