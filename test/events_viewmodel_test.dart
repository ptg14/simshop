import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/event.dart';
import 'package:simshop/services/_http_with_admin_token.dart';
import 'package:simshop/services/event_service.dart';
import 'package:simshop/viewmodels/events_viewmodel.dart';

/// In-memory service used to drive the viewmodel in tests without
/// touching the network. Mirrors the [_FakeArticleService] pattern.
class _FakeEventService implements IEventService {
  _FakeEventService({this.events = const []});

  List<Event> events;
  bool shouldFail = false;
  /// When true, every write method throws
  /// [AdminSessionExpiredException] (mirrors the real service
  /// layer's behavior on a stale 401). Used to pin the viewmodel's
  /// adminSessionExpired-flag flip without spinning up the network.
  bool shouldThrowAdminSessionExpired = false;

  @override
  Future<List<Event>> getEvents() async {
    if (shouldFail) throw Exception('boom');
    return List.unmodifiable(events);
  }

  @override
  Future<Event> createEvent(Event event) async {
    if (shouldThrowAdminSessionExpired) {
      throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
    }
    if (shouldFail) throw Exception('boom');
    final saved = Event(
      id: event.id,
      name: event.name,
      endTime: event.endTime,
      discountType: event.discountType,
      discountValue: event.discountValue,
      productIds: event.productIds,
      createdAt: 1700000000,
    );
    events = [saved, ...events];
    return saved;
  }

  @override
  Future<Event> updateEvent(Event event) async {
    if (shouldThrowAdminSessionExpired) {
      throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
    }
    if (shouldFail) throw Exception('boom');
    events = [
      for (final e in events) if (e.id == event.id) event else e,
    ];
    return event;
  }

  @override
  Future<void> deleteEvent(String id) async {
    if (shouldThrowAdminSessionExpired) {
      throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
    }
    if (shouldFail) throw Exception('boom');
    events = events.where((e) => e.id != id).toList();
  }
}

Event _mkEvent({
  required String id,
  String name = 'Sale',
  Duration? endsIn,
  DiscountType type = DiscountType.percent,
  double value = 10,
  List<String> productIds = const ['p1'],
}) {
  return Event(
    id: id,
    name: name,
    endTime: endsIn == null ? null : DateTime.now().add(endsIn),
    discountType: type,
    discountValue: value,
    productIds: productIds,
  );
}

void main() {
  group('EventsViewModel.load', () {
    test('populates the events list from the service', () async {
      final svc = _FakeEventService(events: [_mkEvent(id: 'e1')]);
      final vm = EventsViewModel(service: svc);
      await vm.load();
      expect(vm.events, hasLength(1));
      expect(vm.events.first.id, 'e1');
      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
    });

    test('captures error message on failure', () async {
      final svc = _FakeEventService()..shouldFail = true;
      final vm = EventsViewModel(service: svc);
      await vm.load();
      expect(vm.events, isEmpty);
      expect(vm.error, contains('Lỗi tải sự kiện'));
      expect(vm.isLoading, isFalse);
    });
  });

  group('EventsViewModel.createEvent', () {
    test('prepends the saved event to the list on success', () async {
      final svc = _FakeEventService();
      final vm = EventsViewModel(service: svc);
      final ok = await vm.createEvent(_mkEvent(id: 'e-new'));
      expect(ok, isTrue);
      expect(vm.events, hasLength(1));
      expect(vm.events.first.id, 'e-new');
    });

    test('returns false and stores error on failure', () async {
      final svc = _FakeEventService()..shouldFail = true;
      final vm = EventsViewModel(service: svc);
      final ok = await vm.createEvent(_mkEvent(id: 'e-bad'));
      expect(ok, isFalse);
      expect(vm.error, contains('Lỗi tạo sự kiện'));
    });
  });

  group('EventsViewModel.updateEvent', () {
    test('replaces the matching event in place', () async {
      final svc = _FakeEventService(events: [_mkEvent(id: 'e1', name: 'Old')]);
      final vm = EventsViewModel(service: svc);
      await vm.load();
      final ok = await vm.updateEvent(_mkEvent(id: 'e1', name: 'New'));
      expect(ok, isTrue);
      expect(vm.events, hasLength(1));
      expect(vm.events.first.name, 'New');
    });
  });

  group('EventsViewModel.deleteEvent', () {
    test('removes the event by id', () async {
      final svc = _FakeEventService(
        events: [_mkEvent(id: 'e1'), _mkEvent(id: 'e2')],
      );
      final vm = EventsViewModel(service: svc);
      await vm.load();
      final ok = await vm.deleteEvent('e1');
      expect(ok, isTrue);
      expect(vm.events, hasLength(1));
      expect(vm.events.first.id, 'e2');
    });
  });

  group('EventsViewModel.activeEvents', () {
    test('returns only events whose endTime is in the future (or null)',
        () async {
      final svc = _FakeEventService(events: [
        _mkEvent(id: 'past', endsIn: const Duration(hours: -1)),
        _mkEvent(id: 'future', endsIn: const Duration(days: 7)),
        _mkEvent(id: 'never', endsIn: null),
      ]);
      final vm = EventsViewModel(service: svc);
      await vm.load();
      final active = vm.activeEvents.map((e) => e.id).toSet();
      expect(active, {'future', 'never'});
      expect(active.contains('past'), isFalse);
    });

    test('sorts active events by soonest endTime first', () async {
      final svc = _FakeEventService(events: [
        _mkEvent(id: 'late', endsIn: const Duration(days: 30)),
        _mkEvent(id: 'soon', endsIn: const Duration(hours: 2)),
        _mkEvent(id: 'mid', endsIn: const Duration(days: 7)),
      ]);
      final vm = EventsViewModel(service: svc);
      await vm.load();
      final ids = vm.activeEvents.map((e) => e.id).toList();
      expect(ids, ['soon', 'mid', 'late']);
    });
  });

  group('EventsViewModel.adminSessionExpired', () {
    test(
      'createEvent flips adminSessionExpired when the service throws '
      'AdminSessionExpiredException (cached token is dead)',
      () async {
        final svc = _FakeEventService()
          ..shouldThrowAdminSessionExpired = true;
        final vm = EventsViewModel(service: svc);

        final ok = await vm.createEvent(_mkEvent(id: 'e-bad'));

        expect(ok, isFalse);
        expect(vm.adminSessionExpired, isTrue,
            reason: 'AdminShell watches this flag (alongside the other '
                'three admin-write viewmodels) and pops the user back '
                'to AdminAuthGate.');
        expect(vm.error, contains('Phiên quản trị đã hết hạn'));
      },
    );

    test(
      'clearAdminSessionExpired() resets the flag without I/O',
      () async {
        final svc = _FakeEventService()
          ..shouldThrowAdminSessionExpired = true;
        final vm = EventsViewModel(service: svc);
        await vm.createEvent(_mkEvent(id: 'e-bad'));
        expect(vm.adminSessionExpired, isTrue);

        // Called by AdminShell.initState on every fresh mount.
        vm.clearAdminSessionExpired();
        expect(vm.adminSessionExpired, isFalse);
      },
    );
  });
}