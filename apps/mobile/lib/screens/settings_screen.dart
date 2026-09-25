import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/household_api.dart';
import '../data/share.dart';
import '../logic/app_store.dart';
import '../logic/push.dart';
import '../logic/session.dart';
import '../logic/ui_state.dart';
import '../shell/router.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/editor_scaffold.dart';
import '../widgets/field.dart';
import '../widgets/switch_row.dart';
import 'join_screen.dart';

/// Settings: reminder preferences, the ladder table and the theme.
///
/// The reminder preferences are persisted here and drive the server's
/// schedule; with [push], turning reminders on asks for notification permission and
/// registers the device, and the server's summary and a test button show
/// beneath the switch. The theme
/// choice writes `Settings.theme`, which `RewardApp` reads from the store
/// into the app's theme mode, so an override takes effect at once. One
/// column at every width, because the ladder table needs it.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    this.ui,
    this.session,
    this.push,
  });

  final AppStore store;
  final UiState? ui;

  /// Push on this device; without it the switch only saves the preference.
  final PushController? push;

  /// Who is signed in, for the account section and sign-out.
  final Session? session;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _time = TextEditingController();
  final _minValue = TextEditingController();
  final _timeFocus = FocusNode(debugLabel: 'time');
  final _minValueFocus = FocusNode(debugLabel: 'min-value');

  /// The invite just made, shown until the screen is left.
  Invite? _invite;

  Future<void> _createInvite() async {
    final role = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => const _InviteRoleSheet(),
    );
    if (role == null) return;
    final invite = await store.createInvite(role);
    if (invite == null || !mounted) return;
    setState(() => _invite = invite);
    await shareText(
      'Join my household on HelpMe Reward: ${invite.link}\n'
      'Or enter the code ${invite.code} under “Have an invite code?”.',
    );
  }

  Future<void> _remove(HouseholdMember member) async {
    final who = member.email ?? 'this member';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $who?'),
        content: const Text(
          'They lose access at once and take nothing with them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await store.removeMember(member.userId);
  }

  Future<void> _enterCode() async {
    final code = await askForInviteCode(context);
    if (code != null && mounted) context.go(invitePath(code));
  }

  AppStore get store => widget.store;
  MemberPreferences get _notifications => store.preferences;

  /// With push, on asks permission and registers first, and a refusal
  /// leaves reminders off with the reason in the snackbar; off saves, then
  /// removes the registration.
  Future<void> _setReminders(bool next) async {
    final push = widget.push;
    if (push == null) {
      await store.updatePreferences((n) => n.copyWith(enabled: next));
      return;
    }
    if (!next) {
      await store.updatePreferences((n) => n.copyWith(enabled: false));
      await push.unregister();
      return;
    }
    final refusal = await push.enable();
    if (refusal != null) {
      widget.ui?.snackbar.show(refusal);
      return;
    }
    await store.updatePreferences((n) => n.copyWith(enabled: true));
    await push.refreshSummary();
  }

  /// "3 reminders scheduled. Next on Oct 31: $10 expires tonight."
  String _summaryText(ReminderSummary? summary) {
    if (summary == null) return 'Reminders come from the server.';
    if (summary.count == 0) return 'Nothing scheduled yet.';
    final count =
        '${summary.count} reminder${summary.count == 1 ? '' : 's'} scheduled.';
    final next = summary.next;
    if (next == null) return count;
    final local = next.fireAt.toLocal();
    final day = formatIsoDate(
      DateParts(year: local.year, month: local.month, day: local.day),
    );
    return '$count Next on ${formatDate(day, store.today)}: ${next.title}.';
  }

  @override
  void initState() {
    super.initState();
    final current = _notifications;
    _time.text = current.timeOfDay;
    _minValue.text = (current.minValueCents / 100).toString();
    _time.addListener(_changed);
    _minValue.addListener(_changed);
    if (current.enabled) widget.push?.refreshSummary();
  }

  @override
  void dispose() {
    _time.dispose();
    _minValue.dispose();
    _timeFocus.dispose();
    _minValueFocus.dispose();
    super.dispose();
  }

  String? get _minValueError => moneyError(_minValue.text);

  /// Writes every valid draft; an invalid minimum waits, showing its error.
  void _changed() {
    final current = _notifications;
    final time = _time.text.trim();
    final cents = parseMoney(_minValue.text);
    final patch = <MemberPreferences Function(MemberPreferences)>[
      if (_timeValid(time) && time != current.timeOfDay)
        (n) => n.copyWith(timeOfDay: time),
      if (cents != null && cents >= 0 && cents != current.minValueCents)
        (n) => n.copyWith(minValueCents: cents),
    ];
    if (patch.isNotEmpty) {
      store.updatePreferences((n) => patch.fold(n, (n, p) => p(n)));
    }
    setState(() {});
  }

  static final RegExp _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
  static bool _timeValid(String value) => _hhmm.hasMatch(value);

  Future<void> _pickTime() async {
    final parts = _time.text.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 9,
            minute: int.tryParse(parts[1]) ?? 0,
          )
        : const TimeOfDay(hour: 9, minute: 0);
    final chosen = await showTimePicker(context: context, initialTime: initial);
    if (chosen != null) {
      _time.text =
          '${chosen.hour.toString().padLeft(2, '0')}:'
          '${chosen.minute.toString().padLeft(2, '0')}';
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Paths.today);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final settings = store.data?.settings;
        if (settings == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return EditorScaffold(
          title: 'Settings',
          onBack: _back,
          snackbar: widget.ui?.snackbar,
          child: Builder(builder: (context) => _body(context, settings)),
        );
      },
    );
  }

  Widget _body(BuildContext context, Settings settings) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final widthClass = WidthClass.of(context);
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);
    final n = store.preferences;

    Widget title(String value) => Semantics(
      header: true,
      headingLevel: 2,
      child: Text(value, style: text.titleSmall),
    );

    return ListView(
      padding: EdgeInsets.all(widthClass.padding),
      children: [
        title('Reminders'),
        const SizedBox(height: Space.s3),
        SwitchRow(
          title: 'Send me reminders',
          note:
              'A tiered ladder per credit, grouped so you get one alert, '
              'not twelve.',
          label: 'Send me reminders',
          value: n.enabled,
          onChanged: _setReminders,
        ),
        if (n.enabled) ...[
          const SizedBox(height: Space.s4),
          Field(
            label: 'Send them at',
            hint: 'A time of day, as HH:MM.',
            error: _timeValid(_time.text.trim())
                ? null
                : 'Enter a time of day, like 09:00.',
            focusNode: _timeFocus,
            builder: (context, control) => TextField(
              key: const Key('field-time'),
              controller: _time,
              focusNode: control.focusNode,
              keyboardType: TextInputType.datetime,
              decoration: control.decoration.copyWith(
                suffixIcon: IconButton(
                  tooltip: 'Pick a time',
                  icon: const Icon(Icons.schedule, size: 18),
                  onPressed: _pickTime,
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.s4),
          Field(
            label: 'Ignore anything under',
            hint: 'In dollars. Cycles worth less get no reminder.',
            error: _minValueError,
            focusNode: _minValueFocus,
            builder: (context, control) => TextField(
              key: const Key('field-min-value'),
              controller: _minValue,
              focusNode: control.focusNode,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: control.decoration,
            ),
          ),
          const SizedBox(height: Space.s4),
          if (widget.push case final push?) ...[
            ListenableBuilder(
              listenable: push,
              builder: (context, _) => Text(
                _summaryText(push.summary),
                key: const Key('reminder-summary'),
                style: note,
              ),
            ),
            const SizedBox(height: Space.s3),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const Key('send-test'),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Send a test notification'),
                onPressed: () async {
                  widget.ui?.snackbar.show(PushController.testPending);
                  final message = await push.sendTest();
                  widget.ui?.snackbar.show(message);
                },
              ),
            ),
          ],
          const SizedBox(height: Space.s4),
          SwitchRow(
            title: 'Nudge me about locked credits',
            note:
                'Credits stuck behind an enrolment box. Off means silence '
                'about money you cannot yet spend.',
            label: 'Nudge me about locked credits',
            value: n.enrollmentReminder,
            onChanged: (next) => store.updatePreferences(
              (n) => n.copyWith(enrollmentReminder: next),
            ),
          ),
        ],
        const SizedBox(height: Space.s8),

        title('The ladder'),
        const SizedBox(height: Space.s2),
        Text(
          'Each cadence gets rungs sized to its window, easing from a '
          'permissive heads-up to a last call. A single credit can be set to '
          'last-call-only from its own sheet.',
          style: note,
        ),
        const SizedBox(height: Space.s3),
        for (final cadence in const [
          Cadence.monthly,
          Cadence.quarterly,
          Cadence.semiannual,
          Cadence.annual,
        ])
          Container(
            key: ValueKey('ladder-${cadence.name}'),
            padding: const EdgeInsets.symmetric(vertical: Space.s2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.surfaceLine)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(cadenceLabel(cadence), style: text.bodyMedium),
                ),
                const SizedBox(width: Space.s3),
                Flexible(
                  child: Text(
                    ladderSummary(cadence),
                    textAlign: TextAlign.end,
                    style: text.bodySmall?.copyWith(
                      color: tokens.accentRamp[300],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.s8),

        title('Appearance'),
        const SizedBox(height: Space.s3),
        Semantics(
          label: 'Appearance',
          container: true,
          explicitChildNodes: true,
          child: Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              for (final (theme, label) in const [
                (ThemeSetting.system, 'System'),
                (ThemeSetting.dark, 'Dark'),
                (ThemeSetting.light, 'Light'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: settings.theme == theme,
                  onSelected: (_) =>
                      store.updateSettings((s) => s.copyWith(theme: theme)),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s2),
        Text(
          'Nocturne is a dark system; the light theme lifts the same ramps '
          'rather than inventing a second palette.',
          style: note,
        ),
        if (store.remote) ..._householdSection(context, title, note),
        if (widget.session case final session?) ...[
          const SizedBox(height: Space.s8),
          title('Account'),
          const SizedBox(height: Space.s2),
          Text(session.user?.email ?? 'Signed in', style: text.bodyMedium),
          const SizedBox(height: Space.s3),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              key: const Key('sign-out'),
              // Unregister while the ID token still works.
              onPressed: () async {
                await widget.push?.unregister();
                await session.auth.signOut();
              },
              child: const Text('Sign out'),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _householdSection(
    BuildContext context,
    Widget Function(String) title,
    TextStyle? note,
  ) {
    final text = Theme.of(context).textTheme;
    final household = store.household;
    final owner = household?.role == MemberRole.owner;
    final invite = _invite;
    return [
      const SizedBox(height: Space.s8),
      title('Household'),
      const SizedBox(height: Space.s2),
      Text(
        'Everyone here shares the same cards and credits. Reminders and '
        'silences stay each person’s own.',
        style: note,
      ),
      const SizedBox(height: Space.s3),
      for (final member in household?.members ?? const <HouseholdMember>[])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s1),
          child: Row(
            children: [
              Expanded(
                child: Text(member.email ?? 'Someone', style: text.bodyMedium),
              ),
              Text(_roleLabel(member.role), style: note),
              if (owner && member.role != MemberRole.owner)
                IconButton(
                  tooltip: 'Remove ${member.email ?? 'this member'}',
                  icon: const Icon(Icons.person_remove_outlined),
                  onPressed: () => _remove(member),
                ),
            ],
          ),
        ),
      const SizedBox(height: Space.s3),
      Wrap(
        spacing: Space.s2,
        runSpacing: Space.s2,
        children: [
          if (owner)
            FilledButton.icon(
              key: const Key('invite'),
              onPressed: _createInvite,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Invite someone'),
            ),
          TextButton(
            key: const Key('have-code'),
            onPressed: _enterCode,
            child: const Text('Have an invite code?'),
          ),
        ],
      ),
      if (invite != null) ...[
        const SizedBox(height: Space.s3),
        Text(
          'Share the link, or read out the code. It works once, for seven '
          'days, and lets them ${invite.role == 'edit' ? 'change' : 'view'} '
          'the household.',
          style: note,
        ),
        const SizedBox(height: Space.s2),
        SelectableText(
          invite.code,
          style: text.headlineSmall?.copyWith(letterSpacing: 4),
        ),
      ],
    ];
  }
}

String _roleLabel(MemberRole role) => switch (role) {
  MemberRole.owner => 'Owner',
  MemberRole.editor => 'Editor',
  MemberRole.reader => 'Reader',
};

/// Read or edit, then make the invite.
class _InviteRoleSheet extends StatefulWidget {
  const _InviteRoleSheet();

  @override
  State<_InviteRoleSheet> createState() => _InviteRoleSheetState();
}

class _InviteRoleSheetState extends State<_InviteRoleSheet> {
  String _role = 'read';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(Space.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Invite someone',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Space.s4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'read', label: Text('Can read')),
              ButtonSegment(value: 'edit', label: Text('Can edit')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.single),
          ),
          const SizedBox(height: Space.s4),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_role),
            child: const Text('Create and share'),
          ),
        ],
      ),
    ),
  );
}
