/// A push sender that records instead of sending, and answers each token
/// as told.
library;

import 'package:api/push.dart';

class FakePush implements PushSender {
  /// Tokens FCM would report as no longer registered.
  final Set<String> unregistered = {};

  /// Every message sent, with the token it went to.
  final List<({String token, PushMessage message})> sent = [];

  @override
  Future<PushResult> send(String token, PushMessage message) async {
    if (unregistered.contains(token)) return PushResult.unregistered;
    sent.add((token: token, message: message));
    return PushResult.sent;
  }

  /// The tags sent to [token], in order.
  List<String> tagsTo(String token) => [
    for (final s in sent)
      if (s.token == token) s.message.tag,
  ];
}
