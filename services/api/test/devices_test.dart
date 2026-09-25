import 'dart:convert';

import 'package:api/api.dart';
import 'package:api/devices.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  const valid = {
    'token': 'fcm-token-1',
    'installationId': 'inst-1',
    'platform': 'ios',
    'timezone': 'Europe/London',
  };

  // @lat: [[api-tests#Devices#Registration body is validated field by field]]
  group('Device.parse', () {
    test('accepts a complete body', () {
      final device = Device.parse(valid);
      expect(device.token, 'fcm-token-1');
      expect(device.installationId, 'inst-1');
      expect(device.platform, 'ios');
      expect(device.timezone, 'Europe/London');
    });

    for (final field in valid.keys) {
      test('names $field when it is missing', () {
        final body = Map.of(valid)..remove(field);
        expect(() => Device.parse(body), throwsInvalidField(field));
      });

      test('names $field when it is blank', () {
        final body = Map.of(valid)..[field] = '  ';
        expect(() => Device.parse(body), throwsInvalidField(field));
      });
    }

    test('rejects a platform other than ios or android', () {
      final body = Map.of(valid)..['platform'] = 'web';
      expect(() => Device.parse(body), throwsInvalidField('platform'));
    });

    test('rejects a timezone that is not shaped like an IANA name', () {
      final body = Map.of(valid)..['timezone'] = 'not a zone!';
      expect(() => Device.parse(body), throwsInvalidField('timezone'));
    });
  });

  // @lat: [[api-tests#Devices#Without sign-in the device routes answer 503]]
  test('the device routes answer 503 when sign-in is not configured', () async {
    final handler = buildHandler();
    final post = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/devices'),
        body: jsonEncode(valid),
        headers: {'content-type': 'application/json'},
      ),
    );
    expect(post.statusCode, 503);
    final body = jsonDecode(await post.readAsString()) as Map<String, dynamic>;
    expect(body['error'], 'no auth');

    final delete = await handler(
      Request('DELETE', Uri.parse('http://localhost/v1/devices/fcm-token-1')),
    );
    expect(delete.statusCode, 503);
  });
}

Matcher throwsInvalidField(String field) =>
    throwsA(isA<InvalidField>().having((e) => e.field, 'field', field));
