import 'package:api/push.dart';
import 'package:test/test.dart';

void main() {
  const message = PushMessage(
    title: r'$10 expires tonight',
    body: r'Dining on Freedom. $10 untouched.',
    tag: 'cardvantage-2026-10-31|urgent',
    data: {'reminderId': '2026-10-31|urgent', 'url': '/?from=notification'},
  );

  // @lat: [[api-tests#Reminder sender#The FCM request carries the copy, the data and the tag]]
  test('the FCM v1 body carries the copy, the data and the tag', () {
    expect(fcmRequestBody('tok', message), {
      'message': {
        'token': 'tok',
        'notification': {
          'title': r'$10 expires tonight',
          'body': r'Dining on Freedom. $10 untouched.',
        },
        'data': {
          'reminderId': '2026-10-31|urgent',
          'url': '/?from=notification',
        },
        'android': {
          'notification': {'tag': 'cardvantage-2026-10-31|urgent'},
        },
        'apns': {
          'headers': {'apns-collapse-id': 'cardvantage-2026-10-31|urgent'},
        },
      },
    });
  });

  // @lat: [[api-tests#Reminder sender#FCM's answer decides the outcome]]
  test('FCM answers map to sent, unregistered and failed', () {
    expect(fcmResult(200, '{"name":"projects/p/messages/1"}'), PushResult.sent);
    expect(
      fcmResult(
        404,
        '{"error":{"status":"NOT_FOUND","details":[{"@type":'
        '"type.googleapis.com/google.firebase.fcm.v1.FcmError",'
        '"errorCode":"UNREGISTERED"}]}}',
      ),
      PushResult.unregistered,
    );
    expect(
      fcmResult(
        400,
        '{"error":{"status":"INVALID_ARGUMENT","details":[{"errorCode":'
        '"INVALID_ARGUMENT"}]}}',
      ),
      PushResult.failed,
    );
    expect(fcmResult(503, 'unavailable'), PushResult.failed);
  });
}
