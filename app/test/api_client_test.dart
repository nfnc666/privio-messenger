import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:privio/core/api_client.dart';

void main() {
  late List<http.BaseRequest> seen;
  late PrivioApiClient api;

  setUp(() {
    seen = [];
    api = PrivioApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient((request) async {
        seen.add(request);
        return http.Response(
          jsonEncode(const {'envelopes': [], 'more': false, 'remaining': 0}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..useToken('token');
  });

  test('a request without a body declares no content type', () async {
    // Declaring JSON on a bodiless request makes a strict server reject it,
    // which silently broke the whole receive loop once.
    await api.fetchEnvelopes();
    await api.acknowledge(7);
    await api.preKeyCount();

    for (final request in seen) {
      expect(
        request.headers.containsKey('content-type'),
        isFalse,
        reason: '${request.method} ${request.url.path} sent a content type with no body',
      );
    }
  });

  test('a request with a body declares JSON', () async {
    await api.addContact('alice');

    final request = seen.single as http.Request;
    expect(request.headers['content-type'], contains('application/json'));
    expect(jsonDecode(request.body), {'username': 'alice'});
  });

  test('the bearer token rides on every request', () async {
    await api.fetchEnvelopes();
    expect(seen.single.headers['authorization'], 'Bearer token');
  });

  test('an error response becomes an ApiException carrying the code', () async {
    final failing = PrivioApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(const {
            'error': 'device_mismatch',
            'message': 'stale',
            'missingDevices': ['device-2'],
          }),
          409,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await expectLater(
      failing.sendMessage(username: 'bob', messages: const []),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'device_mismatch')
            .having((e) => e.missingDevices, 'missingDevices', ['device-2']),
      ),
    );
  });
}
