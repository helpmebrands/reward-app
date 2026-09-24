import 'package:postgres/postgres.dart';

/// Runs [body] in one transaction on [db], a `Connection` or a `Pool`; inside
/// a transaction already it runs in that one.
Future<R> inTransaction<R>(Session db, Future<R> Function(Session tx) body) =>
    switch (db) {
      TxSession() => body(db),
      final SessionExecutor executor => executor.runTx(body),
      _ => throw ArgumentError('cannot open a transaction on $db'),
    };
