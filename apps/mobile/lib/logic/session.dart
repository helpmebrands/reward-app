import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who is signed in, as far as the app needs to know.
@immutable
class SignedInUser {
  const SignedInUser({required this.uid, this.email});

  /// The Firebase user id.
  final String uid;
  final String? email;
}

/// Sign-in, behind an interface so widget tests use a fake: the app's
/// implementation is Firebase Authentication (`FirebaseAuthService`).
abstract interface class AuthService {
  /// The signed-in user, or null when signed out.
  ValueListenable<SignedInUser?> get user;

  Future<void> signInWithGoogle();
  Future<void> signInWithApple();
  Future<void> signOut();

  /// A fresh Firebase ID token for the api, or null when signed out.
  Future<String?> idToken();
}

/// A sign-in that could not happen, with the sentence to show.
class SignInFailed implements Exception {
  const SignInFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The auth of a build with no Firebase configuration for its platform:
/// always signed out, and every sign-in says why.
class UnconfiguredAuth implements AuthService {
  @override
  final ValueNotifier<SignedInUser?> user = ValueNotifier(null);

  static const _message = 'Sign-in is not set up in this build of the app.';

  @override
  Future<void> signInWithGoogle() async => throw const SignInFailed(_message);

  @override
  Future<void> signInWithApple() async => throw const SignInFailed(_message);

  @override
  Future<void> signOut() async {}

  @override
  Future<String?> idToken() async => null;
}

/// Whether the welcome slideshow has been seen on this device. Kept across
/// sign-out, so a returning person goes straight to sign-in.
abstract interface class IntroStore {
  Future<bool> load();
  Future<void> markSeen();
}

class SharedPreferencesIntroStore implements IntroStore {
  const SharedPreferencesIntroStore({this.key = 'intro-seen'});

  final String key;

  @override
  Future<bool> load() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(key) ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> markSeen() async =>
      (await SharedPreferences.getInstance()).setBool(key, true);
}

/// The intro flag in memory: tests and previews.
class MemoryIntroStore implements IntroStore {
  MemoryIntroStore({this.seen = false});

  bool seen;

  @override
  Future<bool> load() async => seen;

  @override
  Future<void> markSeen() async => seen = true;
}

/// The two independent pieces of launch state the router's redirect reads:
/// whether the slideshow has been seen on this device, and who is signed
/// in. Notifies when either changes.
class Session extends ChangeNotifier {
  Session({required this.auth, required this.intro}) {
    auth.user.addListener(notifyListeners);
  }

  final AuthService auth;
  final IntroStore intro;
  bool _introSeen = false;

  bool get introSeen => _introSeen;
  SignedInUser? get user => auth.user.value;
  bool get signedIn => user != null;

  Future<void> load() async {
    _introSeen = await intro.load();
    notifyListeners();
  }

  /// Skip or the last slide: never show the slideshow at launch again.
  Future<void> finishIntro() async {
    _introSeen = true;
    notifyListeners();
    await intro.markSeen();
  }

  @override
  void dispose() {
    auth.user.removeListener(notifyListeners);
    super.dispose();
  }
}
