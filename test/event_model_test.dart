import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/event.dart';

void main() {
  group('Event.applyTo', () {
    test('percent 20% on 100000 yields 80000', () {
      final e = Event(
        id: 'e1',
        discountType: DiscountType.percent,
        discountValue: 20,
      );
      expect(e.applyTo(100000), 80000);
    });

    test('fixed 50000 off 200000 yields 150000', () {
      final e = Event(
        id: 'e1',
        discountType: DiscountType.fixed,
        discountValue: 50000,
      );
      expect(e.applyTo(200000), 150000);
    });

    test('huge fixed discount clamps to zero, never negative', () {
      final e = Event(
        id: 'e1',
        discountType: DiscountType.fixed,
        discountValue: 999999,
      );
      expect(e.applyTo(100), 0);
    });

    test('huge percent discount clamps to zero, never negative', () {
      final e = Event(
        id: 'e1',
        discountType: DiscountType.percent,
        discountValue: 200,
      );
      expect(e.applyTo(100), 0);
    });
  });

  group('Event.isActive', () {
    test('null endTime is always active', () {
      final e = Event(id: 'e1', endTime: null);
      expect(e.isActive(), isTrue);
    });

    test('future endTime is active', () {
      final future = DateTime.now().add(const Duration(days: 7));
      final e = Event(id: 'e1', endTime: future);
      expect(e.isActive(), isTrue);
    });

    test('past endTime is inactive', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final e = Event(id: 'e1', endTime: past);
      expect(e.isActive(), isFalse);
    });
  });

  group('Event.formatDiscount', () {
    test('percent format uses %', () {
      final e = Event(id: 'e1', discountType: DiscountType.percent, discountValue: 20);
      expect(e.formatDiscount(), '-20%');
    });

    test('fixed format uses đ', () {
      final e = Event(id: 'e1', discountType: DiscountType.fixed, discountValue: 50000);
      expect(e.formatDiscount(), '-50000đ');
    });
  });

  group('Event JSON round-trip', () {
    test('toJson emits unix seconds for end_time', () {
      // 2026-01-01 00:00:00 UTC = 1767225600
      final t = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final e = Event(
        id: 'e1',
        name: 'Sale',
        endTime: t,
        discountType: DiscountType.percent,
        discountValue: 15,
        productIds: const ['p1', 'p2'],
      );
      final j = e.toJson();
      expect(j['id'], 'e1');
      expect(j['end_time'], 1767225600);
      expect(j['discount_type'], 'percent');
      expect(j['product_ids'], ['p1', 'p2']);
    });

    test('fromJson reads unix seconds back as DateTime', () {
      final j = {
        'id': 'e1',
        'name': 'Sale',
        'end_time': 1767225600,
        'discount_type': 'percent',
        'discount_value': 15.0,
        'product_ids': ['p1'],
        'created_at': 0,
      };
      final e = Event.fromJson(j);
      expect(e.id, 'e1');
      expect(e.endTime!.isUtc, isTrue);
      expect(e.endTime!.millisecondsSinceEpoch ~/ 1000, 1767225600);
      expect(e.discountType, DiscountType.percent);
      expect(e.productIds, ['p1']);
    });

    test('fromJson handles missing end_time as null', () {
      final j = {
        'id': 'e1',
        'discount_type': 'fixed',
        'discount_value': 100.0,
        'product_ids': <String>[],
      };
      final e = Event.fromJson(j);
      expect(e.endTime, isNull);
    });

    test('fromJson defaults to percent for unknown discount_type', () {
      final j = {
        'id': 'e1',
        'discount_type': 'banana',
        'discount_value': 10.0,
        'product_ids': <String>[],
      };
      final e = Event.fromJson(j);
      expect(e.discountType, DiscountType.percent);
    });
  });

  group('DiscountType.parse', () {
    test('"percent" → percent', () {
      expect(DiscountTypeX.parse('percent'), DiscountType.percent);
    });
    test('"fixed" → fixed', () {
      expect(DiscountTypeX.parse('fixed'), DiscountType.fixed);
    });
    test('null/unknown → percent (safe default)', () {
      expect(DiscountTypeX.parse(null), DiscountType.percent);
      expect(DiscountTypeX.parse('wat'), DiscountType.percent);
    });
  });

  group('Event equality', () {
    test('identical fields → equal', () {
      final a = Event(id: 'e1', discountValue: 10, productIds: const ['p1']);
      final b = Event(id: 'e1', discountValue: 10, productIds: const ['p1']);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different productIds → not equal', () {
      final a = Event(id: 'e1', productIds: const ['p1']);
      final b = Event(id: 'e1', productIds: const ['p2']);
      expect(a, isNot(equals(b)));
    });
  });
}