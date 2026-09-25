/// The server's half of reminders: the sender job Cloud Scheduler runs every
/// 15 minutes, which works out each member's due reminders and pushes them
/// to their devices, and the two routes the app's Settings screen reads.
/// Documented in `lat.md/api/api-architecture.md#Reminder sender`.
library;

import 'package:domain/domain.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import 'auth.dart';
import 'household_data.dart';
import 'preferences.dart';
import 'push.dart';
import 'src/database.dart';
import 'src/responses.dart';
import 'src/routes.dart';
import 'src/signed_in.dart';

/// How late a reminder may still go out. A phone that was off, or a job
/// that failed for a day and a half, should not resurface a stale nudge;
/// the same grace the domain's `dueReminders` gives a device.
const lateLimit = Duration(hours: 36);

/// One reminder of a member's schedule and the real instant it fires.
typedef ScheduledReminder = ({Reminder reminder, DateTime at});

/// The zone [userId]'s reminders keep: their most recently registered
/// device's, or UTC before they have one.
Future<String> memberZone(Session db, String userId) async {
  final rows = await db.execute(
    Sql.named('''
      SELECT timezone FROM devices WHERE user_id = @u::uuid
      ORDER BY updated_at DESC LIMIT 1
    '''),
    parameters: {'u': userId},
  );
  return rows.isEmpty ? 'UTC' : rows.single[0]! as String;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// [data]'s schedule for [prefs] from [from] on, over [horizon] days, with
/// each reminder at its real instant in [zone].
///
/// The domain schedules in the process's local time, which on Cloud Run is
/// UTC and nobody's zone. So the schedule is built from [from] as the
/// member's wall clock reads it, and each reminder's wall-clock time is
/// turned back into an instant by Postgres's tz database, which knows every
/// zone and its daylight saving rules.
Future<List<ScheduledReminder>> scheduleIn(
  Session db,
  AppData data,
  MemberPreferences prefs,
  String zone,
  DateTime from, {
  int horizon = horizonDays,
}) async {
  final wall = await _wallClock(db, zone, from);
  final reminders = buildSchedule(data, prefs, wall, horizon).reminders;
  if (reminders.isEmpty) return const [];
  final walls = [
    for (final r in reminders)
      _wallText(DateTime.fromMillisecondsSinceEpoch(r.fireAt)),
  ];
  final instants = await db.execute(
    Sql.named('''
      SELECT w::timestamp AT TIME ZONE @zone::text
      FROM unnest(@walls::text[]) WITH ORDINALITY AS t(w, i) ORDER BY i
    '''),
    parameters: {'zone': zone, 'walls': TypedValue(Type.textArray, walls)},
  );
  return [
    for (final (i, row) in instants.indexed)
      (reminder: reminders[i], at: (row[0]! as DateTime).toUtc()),
  ];
}

/// [at] as the wall clock in [zone] reads it, as a local `DateTime`.
Future<DateTime> _wallClock(Session db, String zone, DateTime at) async {
  final rows = await db.execute(
    Sql.named('''
      SELECT to_char(@at::timestamptz AT TIME ZONE @zone::text,
                     'YYYY-MM-DD"T"HH24:MI:SS')
    '''),
    parameters: {'at': at.toUtc(), 'zone': zone},
  );
  return DateTime.parse(rows.single[0]! as String);
}

String _wallText(DateTime local) =>
    '${local.year}-${_two(local.month)}-${_two(local.day)} '
    '${_two(local.hour)}:${_two(local.minute)}:00';

/// A member's schedule from [from] on: their household's data, their
/// preferences and mutes, their zone.
Future<List<ScheduledReminder>> memberSchedule(
  Session db,
  Caller member,
  DateTime from, {
  int horizon = horizonDays,
}) => inTransaction(db, (tx) async {
  final zone = await memberZone(tx, member.userId);
  final today = todayIso(await _wallClock(tx, zone, from));
  final household = await loadHousehold(tx, member.householdId, today);
  return scheduleIn(
    tx,
    household.data,
    await preferencesOf(tx, member),
    zone,
    from,
    horizon: horizon,
  );
});

PushMessage _message(Reminder reminder) => PushMessage(
  title: reminder.title,
  body: reminder.body,
  tag: reminder.tag,
  data: {'reminderId': reminder.id, 'url': reminder.url},
);

/// Sends [message] to each of [userId]'s devices, deleting any FCM reports
/// unregistered. Returns how many took it and how many were retired.
Future<({int sent, int retired})> sendToMember(
  Session db,
  PushSender push,
  String userId,
  PushMessage message,
) async {
  final tokens = await db.execute(
    Sql.named('SELECT token FROM devices WHERE user_id = @u::uuid'),
    parameters: {'u': userId},
  );
  var sent = 0;
  var retired = 0;
  for (final [token as String] in tokens) {
    switch (await push.send(token, message)) {
      case PushResult.sent:
        sent++;
      case PushResult.unregistered:
        retired++;
        await db.execute(
          Sql.named('DELETE FROM devices WHERE token = @t'),
          parameters: {'t': token},
        );
      case PushResult.failed:
        break;
    }
  }
  return (sent: sent, retired: retired);
}

/// Sends [message] to [userId]'s devices unless something under [sendId]
/// has already gone to them; returns the pushes delivered.
///
/// The send is recorded before it goes out, so an overlapping run cannot
/// send it too; if no device took it and none was retired, the record is
/// dropped again so the next run retries.
Future<int> sendOnce(
  Session db,
  PushSender push,
  String userId,
  String sendId,
  PushMessage message,
) async {
  final claimed = await db.execute(
    Sql.named('''
      INSERT INTO reminder_sends (user_id, reminder_id)
      VALUES (@u::uuid, @r) ON CONFLICT DO NOTHING
    '''),
    parameters: {'u': userId, 'r': sendId},
  );
  if (claimed.affectedRows == 0) return 0;
  final outcome = await sendToMember(db, push, userId, message);
  if (outcome.sent == 0 && outcome.retired == 0) {
    await db.execute(
      Sql.named('''
        DELETE FROM reminder_sends WHERE user_id = @u::uuid AND reminder_id = @r
      '''),
      parameters: {'u': userId, 'r': sendId},
    );
  }
  return outcome.sent;
}

/// One run of the sender job at [now]: for every member with reminders on
/// and a device, each reminder that fell due in the last [lateLimit] and has
/// not been sent to them goes to all their devices ([sendOnce]). Returns the
/// pushes delivered.
Future<int> sendDueReminders(
  Session db,
  PushSender push, {
  DateTime? now,
}) async {
  final at = (now ?? DateTime.now()).toUtc();
  final since = at.subtract(lateLimit);
  final members = await db.execute('''
    SELECT u.id::text, u.firebase_uid, m.household_id::text, m.role
    FROM users u
    JOIN memberships m ON m.user_id = u.id
    JOIN member_preferences p ON p.user_id = u.id AND p.enabled
    WHERE EXISTS (SELECT 1 FROM devices d WHERE d.user_id = u.id)
  ''');
  var delivered = 0;
  for (final [userId, uid, householdId, role] in members) {
    final member = Caller(
      userId: userId! as String,
      uid: uid! as String,
      householdId: householdId! as String,
      role: Role.values.byName(role! as String),
    );
    // A window of a few days is enough to hold every reminder due now.
    final due = [
      for (final s in await memberSchedule(db, member, since, horizon: 3))
        if (s.at.isAfter(since) && !s.at.isAfter(at)) s.reminder,
    ];
    for (final reminder in due) {
      delivered += await sendOnce(
        db,
        push,
        member.userId,
        reminder.id,
        _message(reminder),
      );
    }
  }
  return delivered;
}

/// Adds `GET /v1/me/reminders/summary` and `POST /v1/me/reminders/test`.
/// Without a [push] sender the test answers 503 `no push`.
void addReminderRoutes(RouteTable routes, SignedIn signedIn, PushSender? push) {
  Future<Response> summary(Request request, Caller caller, Session db) async {
    final schedule = await memberSchedule(db, caller, DateTime.now());
    final next = schedule.isEmpty ? null : schedule.first;
    return jsonResponse({
      'count': schedule.length,
      'next': next == null
          ? null
          : {
              'fireAt': next.at.toIso8601String(),
              'title': next.reminder.title,
              'body': next.reminder.body,
            },
    });
  }

  Future<Response> test(Request request, Caller caller, Session db) async {
    if (push == null) return serviceUnavailable('no push');
    final outcome = await sendToMember(
      db,
      push,
      caller.userId,
      const PushMessage(
        title: 'Test notification',
        body: 'Reminders will arrive like this one.',
        tag: 'helpme-test',
        data: {'url': '/settings'},
      ),
    );
    return jsonResponse({'sent': outcome.sent});
  }

  routes
    ..add('GET', '/v1/me/reminders/summary', signedIn(summary))
    ..add('POST', '/v1/me/reminders/test', signedIn(test));
}
