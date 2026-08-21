import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:FincoreGo/api/api_exception.dart';
import 'package:FincoreGo/api/base_api_client.dart';

/// BaseApiClient reads the active token via `TokenStore`, which is backed
/// by flutter_secure_storage's platform channel - unavailable in a plain
/// `flutter_test` VM run. These tests only care about envelope parsing and
/// refresh/retry sequencing, not what token value gets attached, so the
/// channel is stubbed to always report "no value stored" rather than
/// throwing a MissingPluginException.
void _stubSecureStorageChannel() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => null);
}

http.Response _envelope(
  Map<String, dynamic> body, {
  int statusCode = 200,
}) => http.Response(jsonEncode(body), statusCode);

/// Test double standing in for a real backend client: records how many
/// times [refresh] is invoked and lets each test script the sequence of
/// responses `_send` should see (e.g. 401 then 200 after "refreshing").
class _FakeApiClient extends BaseApiClient {
  _FakeApiClient({required http.Client httpClient})
    : refreshCallCount = 0,
      _refreshShouldThrow = false,
      super('https://fake.test', httpClient: httpClient);

  int refreshCallCount;
  bool _refreshShouldThrow;

  set refreshShouldThrow(bool value) => _refreshShouldThrow = value;

  @override
  Future<void> refresh(TokenScope scope) async {
    refreshCallCount++;
    if (_refreshShouldThrow) {
      throw ApiException(statusCode: 401, code: 'INVALID', message: 'nope');
    }
  }
}

void main() {
  setUpAll(_stubSecureStorageChannel);

  group('BaseApiClient envelope parsing', () {
    test('success envelope returns data', () async {
      final mock = MockClient((request) async {
        return _envelope({
          'success': true,
          'requestId': 'r1',
          'timestamp': '2026-01-01T00:00:00Z',
          'data': {'foo': 'bar'},
        });
      });
      final client = _FakeApiClient(httpClient: mock);

      final result = await client.get('/anything', scope: TokenScope.none);

      expect(result.data, {'foo': 'bar'});
    });

    test('error envelope throws ApiException with code/message', () async {
      final mock = MockClient((request) async {
        return _envelope({
          'success': false,
          'statusCode': 404,
          'error': {'code': 'NOT_FOUND', 'message': 'Unknown ledger'},
        }, statusCode: 404);
      });
      final client = _FakeApiClient(httpClient: mock);

      expect(
        () => client.get('/anything', scope: TokenScope.none),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.code, 'code', 'NOT_FOUND')
              .having((e) => e.message, 'message', 'Unknown ledger'),
        ),
      );
    });
  });

  group('BaseApiClient 401 -> refresh -> retry', () {
    test('retries once after a successful refresh and returns new data', () async {
      var callCount = 0;
      final mock = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return _envelope({
            'success': false,
            'statusCode': 401,
            'error': {'code': 'UNAUTHORIZED', 'message': 'expired'},
          }, statusCode: 401);
        }
        return _envelope({'success': true, 'data': {'ok': true}});
      });
      final client = _FakeApiClient(httpClient: mock);

      final result = await client.get('/anything', scope: TokenScope.user);

      expect(result.data, {'ok': true});
      expect(client.refreshCallCount, 1);
      expect(callCount, 2);
    });

    test(
      'does not retry a second time if the retried request also 401s',
      () async {
        final mock = MockClient((request) async {
          return _envelope({
            'success': false,
            'statusCode': 401,
            'error': {'code': 'UNAUTHORIZED', 'message': 'still expired'},
          }, statusCode: 401);
        });
        final client = _FakeApiClient(httpClient: mock);

        expect(
          () => client.get('/anything', scope: TokenScope.user),
          throwsA(isA<ApiException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(client.refreshCallCount, 1);
      },
    );

    test(
      'a failed refresh surfaces SessionExpiredException, not the raw 401',
      () async {
        final mock = MockClient((request) async {
          return _envelope({
            'success': false,
            'statusCode': 401,
            'error': {'code': 'UNAUTHORIZED', 'message': 'expired'},
          }, statusCode: 401);
        });
        final client = _FakeApiClient(httpClient: mock)
          ..refreshShouldThrow = true;

        expect(
          () => client.get('/anything', scope: TokenScope.user),
          throwsA(isA<SessionExpiredException>()),
        );
      },
    );

    test('a 401 with TokenScope.none is not retried (no token to refresh)', () async {
      var callCount = 0;
      final mock = MockClient((request) async {
        callCount++;
        return _envelope({
          'success': false,
          'statusCode': 401,
          'error': {'code': 'UNAUTHORIZED', 'message': 'expired'},
        }, statusCode: 401);
      });
      final client = _FakeApiClient(httpClient: mock);

      expect(
        () => client.get('/anything', scope: TokenScope.none),
        throwsA(isA<ApiException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.refreshCallCount, 0);
      expect(callCount, 1);
    });
  });
}
