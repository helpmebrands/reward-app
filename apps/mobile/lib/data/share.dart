import 'package:share_plus/share_plus.dart';

/// Hands something to the platform's share sheet. A variable so widget
/// tests can see what would have been shared; the app never reassigns it.
typedef Share = Future<void> Function(ShareParams params);

Share share = shareWithSheet;

/// The share sheet itself, through `share_plus`, a Flutter Favorite.
Future<void> shareWithSheet(ShareParams params) async {
  await SharePlus.instance.share(params);
}
