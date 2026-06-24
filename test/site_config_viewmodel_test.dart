import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/store_info.dart';
import 'package:simshop/services/store_service.dart';
import 'package:simshop/viewmodels/site_config_viewmodel.dart';

/// In-memory service used to drive the viewmodel in tests without
/// touching the network.
class _FakeStoreService implements IStoreService {
  _FakeStoreService([StoreInfo? initial]) : _info = initial ?? const StoreInfo();

  StoreInfo _info;
  int loadCount = 0;
  int updateCount = 0;
  bool shouldFail = false;

  set info(StoreInfo value) => _info = value;

  @override
  Future<StoreInfo> getStoreInfo() async {
    loadCount++;
    if (shouldFail) throw Exception('boom');
    return _info;
  }

  @override
  Future<StoreInfo> updateStoreInfo(StoreInfo info) async {
    updateCount++;
    if (shouldFail) throw Exception('boom');
    _info = info;
    return _info;
  }
}

void main() {
  group('SiteConfigViewModel', () {
    test('load() exposes the service value and notifies listeners', () async {
      final fake = _FakeStoreService(
        const StoreInfo(name: 'Cửa hàng ABC', phone: '0901'),
      );
      final vm = SiteConfigViewModel(service: fake);

      var notifications = 0;
      vm.addListener(() => notifications++);

      await vm.load();

      expect(vm.siteInfo.name, 'Cửa hàng ABC');
      expect(vm.siteInfo.phone, '0901');
      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
      expect(fake.loadCount, 1);
      // at least 2 notifications: start (isLoading=true) and finish
      expect(notifications, greaterThanOrEqualTo(2));
    });

    test('update() persists and notifies on success', () async {
      final fake = _FakeStoreService();
      final vm = SiteConfigViewModel(service: fake);

      await vm.load();
      final ok = await vm.update(
        const StoreInfo(name: 'New', email: 'a@b.com'),
      );

      expect(ok, isTrue);
      expect(vm.siteInfo.name, 'New');
      expect(vm.siteInfo.email, 'a@b.com');
      expect(vm.error, isNull);
      expect(fake.updateCount, 1);
    });

    test('update() preserves old values and sets error on failure', () async {
      final fake = _FakeStoreService(
        const StoreInfo(name: 'Original'),
      );
      final vm = SiteConfigViewModel(service: fake);
      await vm.load();
      expect(vm.siteInfo.name, 'Original');

      fake.shouldFail = true;
      final ok = await vm.update(
        const StoreInfo(name: 'New', email: 'a@b.com'),
      );

      expect(ok, isFalse);
      expect(vm.siteInfo.name, 'Original'); // unchanged
      expect(vm.error, isNotNull);
    });

    test('default model renders "simshop" so the home AppBar never blank', () {
      final vm = SiteConfigViewModel();
      expect(vm.siteInfo.name, 'simshop');
    });
  });
}
