import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

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
import '../widgets/share_choices.dart';
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

  /// View or record usage, then all cards or chosen ones; then the invite,
  /// handed to the share sheet.
  Future<void> _shareCards() async {
    final choice = await showModalBottomSheet<ShareChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ShareChoices(
        title: 'Share your cards',
        cards: store.ownCards,
        action: 'Create and share',
      ),
    );
    if (choice == null) return;
    final invite = await store.createInvite(
      choice.access,
      cardIds: choice.cardIds,
    );
    if (invite == null || !mounted) return;
    setState(() => _invite = invite);
    final box = _shareButton.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    // iOS builds the sheet's header, and the recipient's chat its preview,
    // from the invite page's OpenGraph card, so the link goes alone. Android's
    // sheet fetches nothing, so it gets the message and the icon.
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      await share(
        ShareParams(uri: Uri.parse(invite.link), sharePositionOrigin: origin),
      );
      return;
    }
    final icon = await rootBundle.load('assets/logo/helpmereward-icon.png');
    await share(
      ShareParams(
        text:
            'Help me stop leaving card rewards on the table. Join my '
            "household on HelpMe Reward and we'll track every credit "
            'together, so none expire unused.\n'
            'Code: ${invite.code}\n'
            '${invite.link}',
        title: _inviteTitle,
        subject: _inviteTitle,
        previewThumbnail: XFile.fromData(
          icon.buffer.asUint8List(icon.offsetInBytes, icon.lengthInBytes),
          mimeType: 'image/png',
          name: 'helpmereward-icon.png',
        ),
        sharePositionOrigin: origin,
      ),
    );
  }

  static const _inviteTitle = 'Join my household on HelpMe Reward';

  /// Anchors the share sheet's popover on iPad.
  final _shareButton = GlobalKey();

  /// Changes what someone sees of your cards, or stops sharing with them
  /// after a confirmation.
  Future<void> _changeShare(CardShare given) async {
    final who = given.person.displayName;
    final choice = await showModalBottomSheet<ShareChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ShareChoices(
        title: who,
        cards: store.ownCards,
        action: 'Save',
        access: given.access,
        cardIds: given.allCards ? null : given.cardIds,
        canStop: true,
      ),
    );
    if (choice == null || !mounted) return;
    if (!choice.stop) {
      await store.changeShare(
        given.person.id,
        choice.access,
        cardIds: choice.cardIds,
      );
      return;
    }
    final confirmed = await _confirm(
      title: 'Stop sharing with $who?',
      body: '$who stops seeing your cards at once. Nothing is deleted.',
      action: 'Stop sharing',
    );
    if (confirmed) await store.stopSharing(given.person.id);
  }

  /// Stops seeing someone's cards, after a confirmation.
  Future<void> _stopSeeing(CardShare received) async {
    final who = received.person.displayName;
    final confirmed = await _confirm(
      title: '$who’s cards',
      body:
          'They leave your lists and reminders at once. $who can share them '
          'again.',
      action: 'Stop seeing their cards',
    );
    if (confirmed) await store.stopSeeing(received.person.id);
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

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
    if (store.remote) store.loadShares();
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
                'Credits stuck behind an enrollment box. Off means silence '
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
          child: SegmentedButton<ThemeSetting>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(value: ThemeSetting.system, label: Text('System')),
              ButtonSegment(value: ThemeSetting.dark, label: Text('Dark')),
              ButtonSegment(value: ThemeSetting.light, label: Text('Light')),
            ],
            selected: {settings.theme},
            onSelectionChanged: (next) =>
                store.updateSettings((s) => s.copyWith(theme: next.single)),
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
    final shares = store.shares;
    final invite = _invite;
    Widget subheading(String label) => Padding(
      padding: const EdgeInsets.only(top: Space.s4, bottom: Space.s1),
      child: Semantics(
        header: true,
        child: Text(label, style: text.titleSmall),
      ),
    );
    return [
      const SizedBox(height: Space.s8),
      title('Household'),
      const SizedBox(height: Space.s2),
      Text(
        'People share their cards with each other. Reminders and silences '
        'stay each person’s own.',
        style: note,
      ),
      subheading('People who see your cards'),
      if (shares != null && shares.given.isEmpty)
        Text('Nobody sees your cards yet.', style: note),
      for (final given in shares?.given ?? const <CardShare>[])
        ShareLine(
          key: Key('given-${given.person.id}'),
          share: given,
          onTap: () => _changeShare(given),
        ),
      subheading('Shared with you'),
      if (shares != null && shares.received.isEmpty)
        Text('Nobody shares cards with you yet.', style: note),
      for (final received in shares?.received ?? const <CardShare>[])
        ShareLine(
          key: Key('received-${received.person.id}'),
          share: received,
          onTap: () => _stopSeeing(received),
        ),
      const SizedBox(height: Space.s4),
      Wrap(
        spacing: Space.s2,
        runSpacing: Space.s2,
        children: [
          KeyedSubtree(
            key: _shareButton,
            child: FilledButton.icon(
              key: const Key('share-cards'),
              onPressed: _shareCards,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Share your cards'),
            ),
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
          'days, and lets them view '
          '${invite.allCards ? 'all your cards' : '${invite.cardIds.length} of your cards'}'
          '${invite.access == CardAccess.record ? ' and record what they use' : ''}.',
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

/// One share in Settings: the other person, how many cards and what it
/// lets them do ("All cards · View"), tapped to change or end it.
class ShareLine extends StatelessWidget {
  const ShareLine({super.key, required this.share, required this.onTap});

  final CardShare share;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(share.person.displayName),
    subtitle: Text(
      '${scopeLabel(share.allCards, share.cardIds.length)} · '
      '${accessLabel(share.access)}',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
