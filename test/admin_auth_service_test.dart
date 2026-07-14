import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simshop/services/admin_auth_service.dart';
import 'package:simshop/viewmodels/admin_auth_viewmodel.dart';

/// Fake HTTP client so the service never hits the network. Drives
/// the same JSON shape the Go backend returns for challenge/verify.
class _FakeHttpClient extends http.BaseClient {
  /// Optional flag flipped by tests; default = happy path.
  _FakeHttpClient({this.shouldFailVerify = false});
  bool shouldFailVerify;

  // Fixed 64-hex-char nonce matching the Go backend's `hex.EncodeToString`
  // output. Stable across tests so the assertions can pin it.
  static const String _challengeNonce =
      'cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe';
  static const String _verifyToken = 'abc123';
  static const int _verifyStatus = 200;

  int challengeCalls = 0;
  int verifyCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/challenge')) {
      challengeCalls++;
      return http.StreamedResponse(
        Stream.value(utf8.encode(json.encode({'nonce': _challengeNonce}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path.endsWith('/verify')) {
      verifyCalls++;
      if (shouldFailVerify) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"bad signature"}')),
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode(
          json.encode({
            'token': _verifyToken,
            'expires_at': 1700000000,
          }),
        )),
        _verifyStatus,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path.endsWith('/logout')) {
      return http.StreamedResponse(const Stream.empty(), 204);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      404,
    );
  }
}

/// In-memory service used by viewmodel tests.
class _FakeAdminAuthService implements IAdminAuthService {
  _FakeAdminAuthService({this.shouldFailVerify = false});

  /// When true, [verify] throws with "verify failed". Used by the
  /// failure-state test that asserts the viewmodel surfaces the
  /// verify-specific message. [requestChallenge] always succeeds so
  /// the viewmodel reaches the verify step.
  bool shouldFailVerify;

  String? storedToken;
  int verifyCalls = 0;

  static const String _nonce =
      'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
  static const String _token = 'tok-123';

  @override
  Future<String> requestChallenge() async => _nonce;

  @override
  Future<String> verify({
    required String nonce,
    required String signatureHex,
    required Uint8List secretKeyBytes,
  }) async {
    verifyCalls++;
    if (shouldFailVerify) throw Exception('verify failed');
    storedToken = _token;
    return _token;
  }

  @override
  Future<void> logout() async {
    storedToken = null;
  }

  @override
  Future<String?> getStoredToken() async => storedToken;

  @override
  Future<void> clearStoredToken() async {
    storedToken = null;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RealAdminAuthService', () {
    test('requestChallenge returns nonce from server', () async {
      final fake = _FakeHttpClient();
      final service = RealAdminAuthService(
        baseUrl: 'http://example.test',
        client: fake,
      );
      final nonce = await service.requestChallenge();
      expect(nonce, isNotEmpty);
      expect(fake.challengeCalls, 1);
    });

    test('verify posts multipart and persists the token', () async {
      final fake = _FakeHttpClient();
      final service = RealAdminAuthService(
        baseUrl: 'http://example.test',
        client: fake,
      );
      final token = await service.verify(
        nonce: 'n',
        signatureHex: '00',
        secretKeyBytes: Uint8List.fromList(List.filled(32, 0x42)),
      );
      expect(token, 'abc123');
      expect(fake.verifyCalls, 1);
      expect(await service.getStoredToken(), 'abc123');
    });

    test('verify throws on non-200 and does not persist', () async {
      final fake = _FakeHttpClient(shouldFailVerify: true);
      final service = RealAdminAuthService(
        baseUrl: 'http://example.test',
        client: fake,
      );
      expect(
        () => service.verify(
          nonce: 'n',
          signatureHex: '00',
          secretKeyBytes: Uint8List.fromList(List.filled(32, 0)),
        ),
        throwsException,
      );
      expect(await service.getStoredToken(), isNull);
    });

    test('logout clears stored token', () async {
      final fake = _FakeHttpClient();
      final service = RealAdminAuthService(
        baseUrl: 'http://example.test',
        client: fake,
      );
      await service.verify(
        nonce: 'n',
        signatureHex: '00',
        secretKeyBytes: Uint8List.fromList(List.filled(32, 0)),
      );
      expect(await service.getStoredToken(), isNotNull);
      await service.logout();
      expect(await service.getStoredToken(), isNull);
    });
  });

  group('signEd25519', () {
    test('produces a 64-byte signature for a 32-byte seed', () async {
      // Deterministic seed so the test is reproducible.
      final seed = Uint8List.fromList(List.generate(32, (i) => i));
      final sig = await signEd25519(seed, 'hello');
      expect(sig.length, 64);
    });

    test('different messages produce different signatures', () async {
      final seed = Uint8List.fromList(List.filled(32, 0xab));
      final sig1 = await signEd25519(seed, 'one');
      final sig2 = await signEd25519(seed, 'two');
      expect(sig1, isNot(equals(sig2)));
    });
  });

  group('AdminAuthViewModel', () {
    test('authenticateWithSecretKey transitions idle → loading → success',
        () async {
      final fake = _FakeAdminAuthService();
      final vm = AdminAuthViewModel(service: fake);

      expect(vm.state, AdminAuthState.idle);
      final ok = await vm.authenticateWithSecretKey(
        Uint8List.fromList(List.filled(32, 1)),
      );
      expect(ok, isTrue);
      expect(vm.state, AdminAuthState.success);
      expect(vm.error, isNull);
      expect(fake.verifyCalls, 1);
    });

    test('failure transitions to error with human message', () async {
      final fake = _FakeAdminAuthService(shouldFailVerify: true);
      final vm = AdminAuthViewModel(service: fake);
      final ok = await vm.authenticateWithSecretKey(
        Uint8List.fromList(List.filled(32, 1)),
      );
      expect(ok, isFalse);
      expect(vm.state, AdminAuthState.error);
      expect(vm.error, isNotNull);
      expect(vm.error, contains('verify failed'));
    });

    test('logout clears token and returns to idle', () async {
      final fake = _FakeAdminAuthService();
      final vm = AdminAuthViewModel(service: fake);
      await vm.authenticateWithSecretKey(
        Uint8List.fromList(List.filled(32, 1)),
      );
      expect(vm.state, AdminAuthState.success);
      await vm.logout();
      expect(vm.state, AdminAuthState.idle);
      expect(await fake.getStoredToken(), isNull);
    });

    test('reset clears error state without touching storage', () async {
      final fake = _FakeAdminAuthService(shouldFailVerify: true);
      final vm = AdminAuthViewModel(service: fake);
      await vm.authenticateWithSecretKey(
        Uint8List.fromList(List.filled(32, 1)),
      );
      expect(vm.state, AdminAuthState.error);
      vm.reset();
      expect(vm.state, AdminAuthState.idle);
    });
  });

  group('bytesToHex', () {
    test('formats bytes correctly', () {
      expect(bytesToHex(Uint8List.fromList([0x00, 0xff, 0xab])), '00ffab');
      expect(bytesToHex(Uint8List.fromList([])), '');
    });
  });

  // Touch the cryptography package so the dep stays used in tests.
  test('Ed25519 roundtrip via the cryptography package', () async {
    final seed = Uint8List.fromList(List.generate(32, (i) => i));
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    final sig = await algorithm.sign(utf8.encode('msg'), keyPair: keyPair);
    expect(sig.bytes.length, 64);
  });
}