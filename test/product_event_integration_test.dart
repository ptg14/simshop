import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/event.dart';
import 'package:simshop/models/product.dart';

void main() {
  group('Product with event decoration', () {
    test('effectivePayPrice returns base price when no event', () {
      final p = Product(
        id: 'p1',
        name: 'No sale',
        description: '',
        price: 100000,
        imageUrl: '',
        category: 'test',
        rating: 5,
        specs: const [],
      );
      expect(p.effectivePayPrice, 100000);
      expect(p.currentEvent, isNull);
      expect(p.isOnSale, isFalse);
    });

    test('effectivePayPrice returns effectivePrice when event is active', () {
      final p = Product(
        id: 'p1',
        name: 'Sale',
        description: '',
        price: 100000,
        imageUrl: '',
        category: 'test',
        rating: 5,
        specs: const [],
        effectivePrice: 80000,
        currentEvent: Event(
          id: 'e1',
          discountType: DiscountType.percent,
          discountValue: 20,
        ),
      );
      expect(p.effectivePayPrice, 80000);
      expect(p.isOnSale, isTrue);
      // 20% off → discountPercentage 20
      expect(p.discountPercentage, 20);
    });

    test('isOnSale is true for event-only products', () {
      // Same product but WITHOUT originalPrice set — event alone
      // should mark it as on sale.
      final p = Product(
        id: 'p1',
        name: 'Event only',
        description: '',
        price: 100000,
        imageUrl: '',
        category: 'test',
        rating: 5,
        specs: const [],
        effectivePrice: 70000,
        currentEvent: Event(
          id: 'e1',
          discountType: DiscountType.percent,
          discountValue: 30,
        ),
      );
      expect(p.isOnSale, isTrue);
    });

    test('isOnSale stays true for legacy products with originalPrice', () {
      final p = Product(
        id: 'p1',
        name: 'Manual sale',
        description: '',
        price: 80000,
        originalPrice: 100000,
        imageUrl: '',
        category: 'test',
        rating: 5,
        specs: const [],
      );
      expect(p.isOnSale, isTrue);
      expect(p.discountPercentage, 20);
      // No event → effectivePayPrice falls back to base price.
      expect(p.effectivePayPrice, 80000);
    });

    test('effectivePrice ignored when not actually a discount', () {
      // Defensive: a server bug could send effectivePrice >= price.
      // The customer should still see the base price in that case.
      final p = Product(
        id: 'p1',
        name: 'Bad data',
        description: '',
        price: 100000,
        imageUrl: '',
        category: 'test',
        rating: 5,
        specs: const [],
        effectivePrice: 200000, // higher than price — impossible
        currentEvent: Event(
          id: 'e1',
          discountType: DiscountType.fixed,
          discountValue: 50000,
        ),
      );
      expect(p.effectivePayPrice, 100000);
    });
  });

  group('Product.fromJson with event payload', () {
    test('parses effective_price and current_event when present', () {
      final j = {
        'id': 'p1',
        'name': 'P',
        'description': '',
        'price': 100000,
        'image_url': '',
        'category': 'c',
        'rating': 5,
        'specs': <String>[],
        'effective_price': 75000,
        'current_event': {
          'id': 'e1',
          'discount_type': 'percent',
          'discount_value': 25,
          'product_ids': <String>[],
        },
      };
      final p = Product.fromJson(j);
      expect(p.effectivePrice, 75000);
      expect(p.currentEvent, isNotNull);
      expect(p.currentEvent!.id, 'e1');
      expect(p.isOnSale, isTrue);
    });

    test('handles missing effective_price/current_event (old server)', () {
      final j = {
        'id': 'p1',
        'name': 'P',
        'description': '',
        'price': 100000,
        'image_url': '',
        'category': 'c',
        'rating': 5,
        'specs': <String>[],
      };
      final p = Product.fromJson(j);
      expect(p.effectivePrice, isNull);
      expect(p.currentEvent, isNull);
      expect(p.effectivePayPrice, 100000);
      expect(p.isOnSale, isFalse);
    });
  });
}