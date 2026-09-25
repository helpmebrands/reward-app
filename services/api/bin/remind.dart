import 'dart:io';

import 'package:api/change_notices.dart';
import 'package:api/push.dart';
import 'package:api/reminder_sender.dart';
import 'package:postgres/postgres.dart';

/// One run of the reminder sender: every member's due reminders, then the
/// notices of any catalogue version published since the last run, to their
/// devices through FCM. Cloud Scheduler starts it as the Cloud Run job
/// `reward-api-remind` every 15 minutes. Needs `DATABASE_URL` and
/// `FIREBASE_PROJECT_ID`; exits 2 without either.
Future<void> main() async {
  final url = Platform.environment['DATABASE_URL'] ?? '';
  final project = Platform.environment['FIREBASE_PROJECT_ID'] ?? '';
  if (url.isEmpty || project.isEmpty) {
    stderr.writeln('DATABASE_URL and FIREBASE_PROJECT_ID must both be set');
    exit(2);
  }
  final db = await Connection.openFromUrl(url);
  try {
    final push = FcmSender(project);
    final reminders = await sendDueReminders(db, push);
    final notices = await sendChangeNotices(db, push);
    stdout.writeln('sent $reminders reminder and $notices notice pushes');
  } finally {
    await db.close();
  }
  // The FCM client keeps its connections open; the job is done.
  exit(0);
}
