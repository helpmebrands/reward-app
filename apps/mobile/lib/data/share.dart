import 'package:share_plus/share_plus.dart';

/// Hands text to the platform's share sheet. A variable so widget tests can
/// see what would have been shared; the app never reassigns it.
typedef ShareText = Future<void> Function(String text);

ShareText shareText = shareWithSheet;

/// The share sheet itself, through `share_plus`, a Flutter Favorite.
Future<void> shareWithSheet(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}
