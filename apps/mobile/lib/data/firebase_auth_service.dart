import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../logic/session.dart';

/// Sign-in through Firebase Authentication on the environment's Identity
/// Platform project. Both providers go through `signInWithProvider`, so no
/// provider SDK is added: Apple is native on iOS, Google runs Firebase's
/// web flow and returns through the app's URL scheme.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance {
    _user.value = _map(_auth.currentUser);
    _auth.authStateChanges().listen((user) => _user.value = _map(user));
  }

  final FirebaseAuth _auth;
  final ValueNotifier<SignedInUser?> _user = ValueNotifier(null);

  @override
  ValueListenable<SignedInUser?> get user => _user;

  static SignedInUser? _map(User? user) =>
      user == null ? null : SignedInUser(uid: user.uid, email: user.email);

  Future<void> _signIn(AuthProvider provider) async {
    try {
      await _auth.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      // Closing the sheet is a choice, not an error to show.
      if (e.code == 'canceled' || e.code == 'web-context-canceled') return;
      throw SignInFailed(
        e.message ?? 'Sign-in did not finish (${e.code}). Try again.',
      );
    }
  }

  @override
  Future<void> signInWithGoogle() => _signIn(GoogleAuthProvider());

  @override
  Future<void> signInWithApple() =>
      _signIn(AppleAuthProvider()..addScope('email'));

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();
}
