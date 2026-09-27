/// Invite links that open the app: the association files iOS and Android
/// fetch from the api's own domain before they hand `/invite/…` to the
/// app, and the page a link shows when the app is not installed.
/// Documented in `lat.md/api/api-architecture.md#Invite links`.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'src/responses.dart';
import 'src/routes.dart';

/// Which app may open the invite links, and where to get it.
class AppLinks {
  const AppLinks({
    required this.appleAppIds,
    required this.androidPackage,
    required this.androidFingerprints,
    required this.appStoreUrl,
    required this.playStoreUrl,
    this.inviteImage = const [],
  });

  /// `<team id>.<bundle id>` for each iOS app.
  final List<String> appleAppIds;
  final String androidPackage;

  /// SHA-256 fingerprints of the Android signing certificates, `AA:BB:…`.
  final List<String> androidFingerprints;
  final String appStoreUrl;
  final String playStoreUrl;

  /// The 1200×630 PNG a messenger shows for an invite link, served at
  /// `/og/invite.png`: `assets/invite-og.png`, which the server reads.
  final List<int> inviteImage;

  /// This app's: team `LMFUSVPCDH`, `com.helpmebrands.reward` on both
  /// platforms, the App Store record 6814862386. The Android fingerprints
  /// come from `ANDROID_SHA256_FINGERPRINTS`, since the release key is
  /// Play's.
  static AppLinks fromEnvironment(
    Map<String, String> env, {
    List<int> inviteImage = const [],
  }) => AppLinks(
    appleAppIds: const ['LMFUSVPCDH.com.helpmebrands.reward'],
    androidPackage: 'com.helpmebrands.reward',
    androidFingerprints: [
      for (final f in (env['ANDROID_SHA256_FINGERPRINTS'] ?? '').split(','))
        if (f.trim().isNotEmpty) f.trim(),
    ],
    appStoreUrl: 'https://apps.apple.com/app/id6814862386',
    playStoreUrl:
        'https://play.google.com/store/apps/details?id=com.helpmebrands.reward',
    inviteImage: inviteImage,
  );
}

/// An invite code as `households.dart` makes them.
final _code = RegExp(r'^[A-Z0-9]{4,16}$');

const _escape = HtmlEscape(HtmlEscapeMode.attribute);

/// The message an invite's preview and page carry.
const _title = 'Help me stop leaving card rewards on the table';
const _description =
    "Join my household on HelpMe Reward and we'll track every credit "
    'together, so none expire unused.';

/// Adds the two association files, the fallback invite page and the card
/// image its OpenGraph tags point at. None needs sign-in: the operating
/// system, a browser and a messenger's preview fetch them. [inviteLinkBase]
/// is where invite links point; the page's own link and the image's are
/// made from it.
void addAppLinkRoutes(
  RouteTable routes,
  AppLinks links, {
  required Uri inviteLinkBase,
}) {
  Response appleAssociation(Request request) => jsonResponse({
    'applinks': {
      'details': [
        {
          'appIDs': links.appleAppIds,
          'components': [
            {'/': '/invite/*'},
          ],
        },
      ],
    },
  });

  Response androidAssociation(Request request) => jsonResponse([
    {
      'relation': ['delegate_permission/common.handle_all_urls'],
      'target': {
        'namespace': 'android_app',
        'package_name': links.androidPackage,
        'sha256_cert_fingerprints': links.androidFingerprints,
      },
    },
  ]);

  Response invitePage(Request request) {
    final code = request.params['code']!;
    if (!_code.hasMatch(code)) {
      return jsonResponse({'error': 'not found'}, status: 404);
    }
    final c = _escape.convert(code);
    final url = _escape.convert(inviteLinkBase.resolve(code).toString());
    final image = _escape.convert(
      inviteLinkBase.resolve('/og/invite.png').toString(),
    );
    final title = _escape.convert(_title);
    return Response.ok(
      '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<meta property="og:type" content="website">
<meta property="og:site_name" content="HelpMe Reward">
<meta property="og:title" content="$title">
<meta property="og:description" content="${_escape.convert(_description)}">
<meta property="og:url" content="$url">
<meta property="og:image" content="$image">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="The HelpMe Reward icon beside &ldquo;Stop leaving card rewards on the table&rdquo;">
<meta name="twitter:card" content="summary_large_image">
<meta name="apple-itunes-app" content="app-id=6814862386">
<style>
body{font-family:system-ui,sans-serif;max-width:32rem;margin:3rem auto;padding:0 1rem;line-height:1.5}
.code{font-size:2rem;letter-spacing:.2em;font-weight:600}
a{display:inline-block;margin:.5rem .5rem 0 0}
</style>
</head>
<body>
<h1>$title</h1>
<p>${_escape.convert(_description)}</p>
<p>Install HelpMe Reward, sign in, and enter this code under
&ldquo;Have an invite code?&rdquo;:</p>
<p class="code">$c</p>
<p><a href="${_escape.convert(links.appStoreUrl)}">Get it on the App Store</a>
<a href="${_escape.convert(links.playStoreUrl)}">Get it on Google Play</a></p>
<p>With the app installed, this link opens it directly.</p>
</body>
</html>
''',
      headers: const {'content-type': 'text/html; charset=utf-8'},
    );
  }

  Response inviteImage(Request request) => Response.ok(
    links.inviteImage,
    headers: const {
      'content-type': 'image/png',
      'cache-control': 'public, max-age=86400',
    },
  );

  routes
    ..add('GET', '/.well-known/apple-app-site-association', appleAssociation)
    ..add('GET', '/.well-known/assetlinks.json', androidAssociation)
    ..add('GET', '/invite/<code>', invitePage)
    ..add('GET', '/og/invite.png', inviteImage);
}
