import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/store_info.dart';
import 'package:simshop/services/_http_with_admin_token.dart';
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

  /// When non-null, [updateStoreInfo] throws this instead of the
  /// generic failure. Lets us pin the typed
  /// [AdminSessionExpiredException] branch without going through a
  /// real HTTP layer.
  Object? updateError;

  set info(StoreInfo value) => _info = value;

  @override
  Future<StoreInfo> getStoreInfo() async {
    loadCount++;
    if (shouldFail) throw Exception('boom');
    return _info;
  }

  @override
  Future<StoreInfo> updateStoreInfo(
    StoreInfo info, {
    String? oldBannerUrl,
  }) async {
    updateCount++;
    if (updateError != null) throw updateError!;
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

    test(
        'update() flips adminSessionExpired when the service throws '
        'AdminSessionExpiredException (cached token is dead)', () async {
      final fake = _FakeStoreService(
        const StoreInfo(name: 'Original'),
      );
      final vm = SiteConfigViewModel(service: fake);
      await vm.load();
      expect(vm.adminSessionExpired, isFalse);

      fake.updateError = AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
      final ok = await vm.update(const StoreInfo(name: 'New'));

      expect(ok, isFalse);
      expect(vm.adminSessionExpired, isTrue,
          reason: 'admin shell pops back to auth gate when this is true');
      expect(vm.siteInfo.name, 'Original',
          reason: 'failed write must not overwrite local model');
      expect(vm.error, isNotNull,
          reason: 'user sees the localized message in the snackbar');
    });
  });

  // Slice 2: pin the JSON wire format for the new google_maps_url
  // field. Must match the Go server tag `google_maps_url` exactly so
  // the strict JSON decoder doesn't 400 (see lib/models/article.dart
  // for a previous bug in the same shape).
  group('StoreInfo JSON wire format', () {
    test('fromJson reads google_maps_url from the Go server response', () {
      final info = StoreInfo.fromJson({
        'id': 1,
        'name': 'Cửa hàng ABC',
        'address': '12 Nguyễn Huệ',
        'google_maps_url':
            'https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue',
      });
      expect(info.googleMapsUrl,
          'https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue');
    });

    test('toJson writes google_maps_url (matches Go server tag)', () {
      const info = StoreInfo(
        name: 'Cửa hàng ABC',
        googleMapsUrl:
            'https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue',
      );
      final json = info.toJson();
      expect(json['google_maps_url'],
          'https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue');
      // No 'body' or other shape mismatches.
      expect(json.containsKey('googleMapsUrl'), isFalse,
          reason: 'client must send snake_case to match Go tag');
    });

    test('default googleMapsUrl is empty and isEmpty stays correct', () {
      const info = StoreInfo(name: 'X');
      expect(info.googleMapsUrl, '');
      expect(info.isEmpty, isFalse,
          reason: 'name is set so isEmpty must be false');

      const blank = StoreInfo.empty();
      expect(blank.isEmpty, isTrue);
    });

    test('copyWith preserves untouched fields', () {
      const a = StoreInfo(name: 'A', googleMapsUrl: 'https://x');
      final b = a.copyWith(address: '12 Nguyễn Huệ');
      expect(b.name, 'A');
      expect(b.googleMapsUrl, 'https://x',
          reason: 'untouched field must survive copyWith');
      expect(b.address, '12 Nguyễn Huệ');
    });
  });
}
