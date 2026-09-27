import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:api/api.dart';
import 'package:api/app_links.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// The files that let an invite link open the app (iOS universal links and
/// Android App Links) and the page it opens without the app.
void main() {
  const links = AppLinks(
    appleAppIds: ['TEAMID.com.example.app'],
    androidPackage: 'com.example.app',
    androidFingerprints: ['AA:BB'],
    appStoreUrl: 'https://apps.apple.com/app/id1',
    playStoreUrl: 'https://play.google.com/store/apps/details?id=com.example',
    inviteImage: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3],
  );
  final handler = buildHandler(
    appLinks: links,
    inviteLinkBase: Uri.parse('https://api.example.test/invite/'),
  );

  Future<Response> get(String path) =>
      Future.value(handler(Request('GET', Uri.parse('http://localhost$path'))));

  // @lat: [[api-tests#Invite links#The app claims the invite path on iOS]]
  test('the apple-app-site-association claims /invite/* for the app', () async {
    final response = await get('/.well-known/apple-app-site-association');
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], startsWith('application/json'));
    final body = jsonDecode(await response.readAsString()) as Map;
    final details =
        ((body['applinks'] as Map)['details'] as List).single as Map;
    expect(details['appIDs'], ['TEAMID.com.example.app']);
    expect(details['components'], [
      {'/': '/invite/*'},
    ]);
  });

  // @lat: [[api-tests#Invite links#The app claims the invite path on Android]]
  test('assetlinks.json names the package and its certificates', () async {
    final response = await get('/.well-known/assetlinks.json');
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString()) as List;
    final statement = body.single as Map;
    expect(statement['relation'], [
      'delegate_permission/common.handle_all_urls',
    ]);
    expect(statement['target'], {
      'namespace': 'android_app',
      'package_name': 'com.example.app',
      'sha256_cert_fingerprints': ['AA:BB'],
    });
  });

  // @lat: [[api-tests#Invite links#Without the app an invite shows its code]]
  test('/invite/{code} is a page with the code and both stores', () async {
    final response = await get('/invite/ABCD2345');
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], startsWith('text/html'));
    final html = await response.readAsString();
    expect(html, contains('ABCD2345'));
    expect(html, contains('https://apps.apple.com/app/id1'));
    expect(html, contains('https://play.google.com/store/apps/details'));
    expect((await get('/invite/not<a>code')).statusCode, 404);
  });

  // @lat: [[api-tests#Invite links#An invite link previews as the card]]
  test('the invite page carries OpenGraph tags for the card', () async {
    final html = await (await get('/invite/ABCD2345')).readAsString();
    String meta(String key) {
      final match = RegExp(
        '<meta (?:property|name)="${RegExp.escape(key)}" content="([^"]*)">',
      ).firstMatch(html);
      expect(match, isNotNull, reason: '$key is missing');
      return match!.group(1)!;
    }

    expect(meta('og:type'), 'website');
    expect(meta('og:site_name'), 'HelpMe Reward');
    expect(meta('og:title'), 'Help me stop leaving card rewards on the table');
    expect(
      meta('og:description'),
      'Join my household on HelpMe Reward and we&#39;ll track every credit '
      'together, so none expire unused.',
    );
    expect(meta('og:url'), 'https://api.example.test/invite/ABCD2345');
    expect(meta('og:image'), 'https://api.example.test/og/invite.png');
    expect(meta('og:image:width'), '1200');
    expect(meta('og:image:height'), '630');
    expect(meta('og:image:alt'), isNotEmpty);
    expect(meta('twitter:card'), 'summary_large_image');
    expect(meta('apple-itunes-app'), 'app-id=6814862386');
    expect(
      html,
      contains('<title>Help me stop leaving card rewards on the table</title>'),
    );
    expect(
      html,
      contains('<h1>Help me stop leaving card rewards on the table</h1>'),
    );
  });

  // @lat: [[api-tests#Invite links#The card image is served without sign-in]]
  test('/og/invite.png answers the card as a PNG', () async {
    final response = await get('/og/invite.png');
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'image/png');
    expect(response.headers['cache-control'], contains('max-age='));
    final bytes = await response.read().expand((b) => b).toList();
    expect(bytes, links.inviteImage);
  });

  // @lat: [[api-tests#Invite links#The committed card is a small PNG]]
  test('the committed card is a 1200x630 PNG under 300 KB', () {
    final bytes = File('assets/invite-og.png').readAsBytesSync();
    expect(bytes.take(8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    expect(bytes.length, lessThan(300 * 1024));
    int u32(int at) => ByteData.sublistView(bytes, at, at + 4).getUint32(0);
    expect((u32(16), u32(20)), (1200, 630));
  });
}
