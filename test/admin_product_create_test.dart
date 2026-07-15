import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/_http_with_admin_token.dart';
import 'package:simshop/services/i_product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';

/// In-memory [IProductService] that lets a test inject the exception
/// (or return value) of [createProduct] / [uploadImage] / [uploadImages]
/// without going through real HTTP. Mirrors the shape of the fakes
/// in admin_product_filter_test.dart but adds the typed-exception
/// hooks needed by the session-expiry tests below.
class _FakeProductService implements IProductService {
  /// When non-null, [createProduct] throws this value verbatim — used
  /// by the session-expiry test to pin the AdminSessionExpiredException
  /// branch without HTTP. Production paths flow the exception from
  /// `detectAdminSessionExpiry` in [_http_with_admin_token.dart].
  Object? createError;

  /// When non-null, [uploadImage] throws this value. The single-file
  /// upload branch in [AdminViewModel.addProduct] swallows it as a
  /// generic upload error (not a session-expiry redirect), so this
  /// hook is here mostly for symmetry / future tests.
  Object? uploadError;

  /// When non-null, [uploadImages] throws this value. Like
  /// [uploadError] this is best-effort plumbing for future tests;
  /// the multi-file branch is what [addProduct] hits when the user
  /// picks more than one image.
  Object? uploadImagesError;

  /// Fixed URL returned by the upload stubs when no error is set.
  static const String _uploadedUrl = 'https://example.test/uploaded.jpg';

  int createCalls = 0;
  int uploadImageCalls = 0;
  int uploadImagesCalls = 0;

  @override
  Future<List<Product>> getAllProducts() async => const [];

  @override
  Future<List<Product>> getProductsByCategory(String category) async => const [];

  @override
  Future<Product> getProductById(String id) async =>
      throw UnimplementedError();

  @override
  Future<List<Product>> searchProducts(String query) async => const [];

  @override
  Future<void> deleteCategory(String name) async {}

  @override
  Future<List<String>> getLargeCategories() async => const [];

  @override
  Future<List<Category>> getCategoriesWithParent() async => const [];

  @override
  Future<void> createLargeCategory(String name) async {}

  @override
  Future<void> deleteLargeCategory(String name) async {}

  @override
  Future<void> createCategoryWithParent(
          String name, String largeCategoryName) async {}

  @override
  Future<Product> createProduct(
    Product product, {
    List<String>? removedImageUrls,
  }) async {
    createCalls++;
    if (createError != null) throw createError!;
    return product;
  }

  @override
  Future<Product> updateProduct(
    String id,
    Product product, {
    List<String>? removedImageUrls,
  }) async =>
      product;

  @override
  Future<Product> updateStock(String id, int? stock) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteProduct(String id) async {}

  @override
  Future<String?> uploadImage(
    dynamic file, {
    String? productName,
    String? productId,
    int startIndex = 1,
  }) async {
    uploadImageCalls++;
    if (uploadError != null) throw uploadError!;
    return _uploadedUrl;
  }

  @override
  Future<List<String>> uploadImages(
    List<dynamic> files, {
    String? productName,
    String? productId,
    int startIndex = 1,
  }) async {
    uploadImagesCalls++;
    if (uploadImagesError != null) throw uploadImagesError!;
    return [_uploadedUrl];
  }
}

Product _newProduct() => Product(
      id: '',
      name: 'Áo thun mới',
      description: 'Mô tả',
      price: 199000,
      imageUrl: '',
      category: 'All',
      categories: const ['All'],
      rating: 0,
      stock: 10,
      specs: const [],
    );

void main() {
  group('AdminViewModel.addProduct', () {
    test(
      'flips adminSessionExpired when the service throws '
      'AdminSessionExpiredException (cached token is dead)',
      () async {
        // Regression test for the production bug: when the cached
        // Bearer token is rejected by the server (e.g. after a
        // restart), POST /api/products returns 401, the service layer
        // clears the local token and throws AdminSessionExpiredException
        // via detectAdminSessionExpiry. AdminViewModel.addProduct
        // used to swallow it as a generic "Lỗi thêm sản phẩm: ..."
        // string, leaving the user stranded on a dead session with no
        // way to re-authenticate. The shell listens for the typed
        // flag and pops back to AdminAuthGate; the viewmodel MUST
        // set it.
        final svc = _FakeProductService()
          ..createError = AdminSessionExpiredException(
            'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
          );
        final vm = AdminViewModel(productService: svc);
        expect(vm.adminSessionExpired, isFalse);

        await vm.addProduct(_newProduct());

        expect(vm.adminSessionExpired, isTrue,
            reason: 'admin shell pops back to auth gate when this is true');
        expect(vm.error, isNotNull,
            reason: 'user sees the localized message in the snackbar');
        expect(vm.error,
            contains('Phiên quản trị đã hết hạn'),
            reason: 'error must surface the expired-session message, not '
                'wrap it as "Lỗi thêm sản phẩm: <exception>"');
      },
    );

    test(
      'keeps generic exception wrapping on non-session errors',
      () async {
        // Sanity check: addProduct must still wrap ordinary failures
        // (network drop, 500, validation 400) in the localized
        // "Lỗi thêm sản phẩm:" prefix so the existing error banner
        // UX stays intact. Only the typed
        // AdminSessionExpiredException gets the special-cased
        // treatment.
        final svc = _FakeProductService()
          ..createError = Exception('boom');
        final vm = AdminViewModel(productService: svc);

        await vm.addProduct(_newProduct());

        expect(vm.adminSessionExpired, isFalse,
            reason: 'generic failure must NOT trigger re-auth redirect');
        expect(vm.error, contains('Lỗi thêm sản phẩm'));
        expect(vm.error, contains('boom'));
      },
    );

    test('happy path still works and clears isLoading', () async {
      final svc = _FakeProductService();
      final vm = AdminViewModel(productService: svc);

      await vm.addProduct(_newProduct());

      expect(svc.createCalls, 1);
      expect(vm.adminSessionExpired, isFalse);
      expect(vm.error, isNull);
      expect(vm.isLoading, isFalse,
          reason: 'isLoading must be reset on success');
    });

    test(
      'clears a stale adminSessionExpired flag on entry so a prior 401 '
      'cannot poison a subsequent successful create',
      () async {
        // Regression test for the production bug the previous fix
        // accidentally unlocked: once a 401 sets [_adminSessionExpired],
        // the AdminShell pops the admin back to AdminAuthGate. After
        // re-auth the same [AdminViewModel] instance is reused (it
        // lives at the root MultiProvider, not on the AdminShell),
        // so [_adminSessionExpired] is *still true* unless addProduct
        // clears it on entry. With the flag stuck, every subsequent
        // successful create immediately fires the shell's redirect →
        // admin → gate → admin → gate loop.
        //
        // [updateProduct] already does this reset on entry (see
        // AdminViewModel.updateProduct line ~329). [addProduct] must
        // match it so the two create/update twins behave identically.
        final svc = _FakeProductService();
        final vm = AdminViewModel(productService: svc);

        // Simulate the stale-flag state left behind by a previous
        // 401 — either in this same VM or in a prior session that
        // never reset the flag. The simplest way to flip the flag
        // to true without re-running the catch branch is to drive
        // the viewmodel through one failing createProduct call.
        svc.createError = AdminSessionExpiredException(
          'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
        );
        await vm.addProduct(_newProduct());
        expect(vm.adminSessionExpired, isTrue,
            reason: 'precondition: the failed call must have set the flag');

        // Now flip the service back to "happy" and re-call — the
        // viewmodel must clear the flag at the start of the next
        // attempt so the shell doesn't kick the admin out of a
        // successful save.
        svc.createError = null;
        await vm.addProduct(_newProduct());

        expect(vm.adminSessionExpired, isFalse,
            reason: 'addProduct must reset the stale flag on entry so the '
                'shell does not redirect mid-success (admin ↔ gate loop)');
        expect(vm.error, isNull,
            reason: 'a fresh, successful create must not carry over the '
                'previous error message');
        expect(vm.isLoading, isFalse);
        expect(svc.createCalls, 2,
            reason: 'both attempts should reach the service');
      },
    );
  });
}
