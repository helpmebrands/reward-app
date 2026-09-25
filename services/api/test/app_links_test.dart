import 'dart:convert';

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
  );
  final handler = buildHandler(appLinks: links);

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
}
