import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';

/// Verifies that the "Thử lại" (retry) button on the admin products
/// screen actually recovers from a stale error state. The button is
/// wired to [AdminViewModel.initialize] (see
/// `lib/views/admin/admin_product/admin_product_screen.dart:112`),
/// so this test guards the contract that a re-`initialize()` after a
/// failed write clears [AdminViewModel.error] — otherwise the error
/// view stays painted and the retry button has no visible effect.
///
/// Related: the `HomeViewModel` analogue (`loadProducts`) already
/// resets `_error = null` at the top of the method, so the home retry
/// works. [AdminViewModel.initialize] used to swallow the
/// `getAllProducts()` failure with `catch (_)` and never reset
/// `_error`, so any prior write-failure error stuck around and made
/// the retry button feel "completely broken".
class _InMemoryService implements IProductService {
  _InMemoryService();

  /// Behaviour toggle for [getAllProducts]. When non-null, the method
  /// throws; otherwise it returns [_products].
  Exception? nextGetAllError;

  /// Toggles [getAllProducts] between throwing and returning data, so
  /// a single test can drive the failure → recovery arc.
  bool failNextGetAll = false;

  final List<Product> _products = [];

  int getAllCalls = 0;

  @override
  Future<List<Product>> getAllProducts() async {
    getAllCalls += 1;
    if (failNextGetAll) {
      throw Exception('boom');
    }
    return List.of(_products);
  }

  @override
  Future<List<Product>> getProductsByCategory(String category) async => _products;
  @override
  Future<Product> getProductById(String id) async => _products.first;
  @override
  Future<List<Product>> searchProducts(String query) async => _products;
  @override
  Future<void> deleteProduct(String id) async {}
  @override
  Future<Product> createProduct(Product product, {List<String>? removedImageUrls}) async => product;
  @override
  Future<Product> updateProduct(String id, Product product, {List<String>? removedImageUrls}) async => product;
  @override
  Future<Product> updateStock(String id, int? stock) async => throw UnimplementedError();
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
  Future<void> createCategoryWithParent(String name, String largeCategoryName) async {}
  @override
  Future<String?> uploadImage(dynamic file, {String? productName, String? productId, int startIndex = 1}) async => null;
  @override
  Future<List<String>> uploadImages(List<dynamic> files, {String? productName, String? productId, int startIndex = 1}) async => const [];
}

void main() {
  group('AdminViewModel retry flow', () {
    test('initialize() clears a stale error so the retry button can recover', () async {
      final svc = _InMemoryService();
      final vm = AdminViewModel(productService: svc);

      // Simulate a prior write that left _error set (e.g. addProduct
      // failing on a network blip). The exact message isn't important
      // — just that *something* is sitting in [error].
      // Reaching for the private field would be brittle, so we go
      // through a public surface: [toggleFilterSub] and friends don't
      // set _error, but [clearFilter] doesn't either. Easiest: just
      // call initialize twice with a failing service once + once OK
      // and observe the final state.
      svc.failNextGetAll = true;
      await vm.initialize();

      // If the load actually failed, _error should be set so the UI
      // can show the retry screen. Today, AdminViewModel silently
      // swallows the error, leaving [error] == null — which means
      // the UI thinks the load succeeded and silently shows an empty
      // list. That's still broken: no message → user has no idea why
      // the list is empty. After the fix we expect [error] to be a
      // non-null descriptive message.
      expect(vm.error, isNotNull,
          reason: 'initialize() must capture getAllProducts() failures '
              'so the admin screen can show an error view + retry button.');

      // Now the network "recovers". The retry button calls
      // initialize() again. The stale error MUST be cleared so the
      // screen flips from the error view back to the loaded grid.
      svc.failNextGetAll = false;
      await vm.initialize();

      expect(vm.error, isNull,
          reason: 'initialize() must reset a stale error so the retry '
              'button (which calls initialize) can transition the UI '
              'out of the error view. Otherwise the button feels broken.');
    });
  });
}
