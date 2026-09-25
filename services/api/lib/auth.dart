/// Sign-in: Firebase ID tokens from Identity Platform, verified here, and
/// the user row each verified caller gets. Documented in
/// `lat.md/api/api-architecture.md#Sign-in`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart';

import 'src/database.dart';

/// A token that failed verification, and why; the caller only ever sees 401.
class InvalidToken implements Exception {
  const InvalidToken(this.reason);

  final String reason;

  @override
  String toString() => 'invalid token: $reason';
}

/// Who a verified token speaks for.
class VerifiedToken {
  const VerifiedToken({required this.uid, this.email});

  /// The Firebase user id, `sub`.
  final String uid;
  final String? email;
}

/// Turns a bearer token into a [VerifiedToken] or throws [InvalidToken].
/// An interface so handler tests can stand in their own.
abstract interface class TokenVerifier {
  Future<VerifiedToken> verify(String token);
}

/// Google's current signing certificates for Firebase ID tokens, by key id,
/// with how long they may be cached.
typedef CertificateFetch =
    Future<({Map<String, String> certs, Duration maxAge})> Function();

/// Where Google publishes the certificates that sign Firebase ID tokens.
final Uri firebaseCertificatesUrl = Uri.parse(
  'https://www.googleapis.com/robot/v1/metadata/x509/'
  'securetoken@system.gserviceaccount.com',
);

/// The certificates, fetched once and kept for the `max-age` Google sends,
/// so a request never waits on Google unless the keys have rotated.
class GoogleCertificates {
  GoogleCertificates({CertificateFetch? fetch, DateTime Function()? clock})
    : _fetch = fetch ?? fetchFirebaseCertificates,
      _clock = clock ?? DateTime.now;

  final CertificateFetch _fetch;
  final DateTime Function() _clock;
  Map<String, String> _certs = const {};
  DateTime _expires = DateTime.utc(1970);

  Future<Map<String, String>> current() async {
    if (!_clock().isBefore(_expires)) {
      final fetched = await _fetch();
      _certs = fetched.certs;
      _expires = _clock().add(fetched.maxAge);
    }
    return _certs;
  }
}

/// Fetches [firebaseCertificatesUrl] with `dart:io`, no client package.
Future<({Map<String, String> certs, Duration maxAge})>
fetchFirebaseCertificates() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(firebaseCertificatesUrl);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('certificates: ${response.statusCode}');
    }
    return (
      certs: (jsonDecode(body) as Map<String, dynamic>).cast<String, String>(),
      maxAge: maxAgeOf(response.headers.value('cache-control')),
    );
  } finally {
    client.close();
  }
}

/// The `max-age` of a `Cache-Control` header; zero when there is none.
Duration maxAgeOf(String? cacheControl) {
  final match = RegExp(r'max-age=(\d+)').firstMatch(cacheControl ?? '');
  return Duration(seconds: match == null ? 0 : int.parse(match[1]!));
}

/// Verifies a Firebase ID token the way Firebase documents it: RS256 only,
/// signed by a key Google currently publishes, issued by
/// `securetoken.google.com/<project>` for this project, unexpired, issued
/// and authenticated in the past, naming a user.
class FirebaseTokenVerifier implements TokenVerifier {
  FirebaseTokenVerifier({required this.projectId, required this.certificates});

  final String projectId;
  final GoogleCertificates certificates;

  /// Clock skew allowed on `iat` and `auth_time`.
  static const skew = Duration(minutes: 5);

  @override
  Future<VerifiedToken> verify(String token) async {
    final JWT unverified;
    try {
      unverified = JWT.decode(token);
    } on Object {
      throw const InvalidToken('malformed');
    }
    final header = unverified.header ?? const {};
    // The algorithm is fixed, never taken from the token: a token that
    // names HS256 would otherwise be checked with the public key as secret.
    if (header['alg'] != 'RS256') throw const InvalidToken('algorithm');
    final cert = (await certificates.current())[header['kid']];
    if (cert == null) throw const InvalidToken('unknown key');

    final JWT jwt;
    try {
      jwt = JWT.verify(
        token,
        RSAPublicKey.cert(cert),
        checkHeaderType: false,
        audience: Audience.one(projectId),
        issuer: 'https://securetoken.google.com/$projectId',
      );
    } on JWTExpiredException {
      throw const InvalidToken('expired');
    } on JWTException catch (e) {
      throw InvalidToken(e.message);
    }

    final claims = jwt.payload as Map<String, dynamic>;
    final sub = claims['sub'];
    if (sub is! String || sub.isEmpty) throw const InvalidToken('subject');
    final latest = DateTime.now().toUtc().add(skew);
    for (final claim in ['iat', 'auth_time']) {
      final seconds = claims[claim];
      if (seconds is! num ||
          DateTime.fromMillisecondsSinceEpoch(
            (seconds * 1000).toInt(),
            isUtc: true,
          ).isAfter(latest)) {
        throw InvalidToken(claim);
      }
    }
    return VerifiedToken(uid: sub, email: claims['email'] as String?);
  }
}

/// A member's role in their household: the owner manages members, editors
/// change the data, readers only read it.
enum Role {
  owner,
  editor,
  reader;

  bool get canWrite => this != reader;
}

/// The signed-in user a request acts for, and the household they are in.
class Caller {
  const Caller({
    required this.userId,
    required this.uid,
    this.email,
    required this.householdId,
    required this.role,
  });

  /// The `users.id` row.
  final String userId;

  /// The Firebase uid.
  final String uid;
  final String? email;
  final String householdId;
  final Role role;

  Map<String, Object?> toJson() => {'id': userId, 'email': email};
}

/// The user row for [token] and their household. The first authenticated
/// call creates both, the user owning a new, empty household; a later call
/// keeps them and refreshes the email. One transaction: the upsert locks
/// the user's row, so two first calls cannot make two households.
Future<Caller> callerFor(Session db, VerifiedToken token) =>
    inTransaction(db, (tx) async {
      final user = (await tx.execute(
        Sql.named('''
          INSERT INTO users (firebase_uid, email) VALUES (@uid, @email)
          ON CONFLICT (firebase_uid) DO UPDATE
            SET email = COALESCE(EXCLUDED.email, users.email)
          RETURNING id::text, email
        '''),
        parameters: {'uid': token.uid, 'email': token.email},
      )).single;
      final userId = user[0]! as String;
      var membership = await tx.execute(
        Sql.named(
          'SELECT household_id::text, role FROM memberships '
          'WHERE user_id = @user::uuid',
        ),
        parameters: {'user': userId},
      );
      if (membership.isEmpty) {
        membership = await tx.execute(
          Sql.named('''
            WITH household AS (
              INSERT INTO households DEFAULT VALUES RETURNING id
            )
            INSERT INTO memberships (household_id, user_id, role)
            SELECT id, @user::uuid, 'owner' FROM household
            RETURNING household_id::text, role
          '''),
          parameters: {'user': userId},
        );
      }
      return Caller(
        userId: userId,
        uid: token.uid,
        email: user[1] as String?,
        householdId: membership.single[0]! as String,
        role: Role.values.byName(membership.single[1]! as String),
      );
    });
