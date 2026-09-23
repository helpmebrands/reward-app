import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../logic/ui_state.dart';
import '../shell/router.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/editor_scaffold.dart';
import '../widgets/field.dart';
import '../widgets/switch_row.dart';

/// Settings: reminder preferences, the ladder table and the theme.
///
/// The reminder preferences are persisted here and drive the nudge preview;
/// delivery on the device, with its permission, is a later epic. The theme
/// choice writes `Settings.theme`, which `RewardApp` reads from the store
/// into the app's theme mode, so an override takes effect at once. One
/// column at every width, because the ladder table needs it.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store, this.ui});

  final AppStore store;
  final UiState? ui;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _time = TextEditingController();
  final _minValue = TextEditingController();
  final _timeFocus = FocusNode(debugLabel: 'time');
  final _minValueFocus = FocusNode(debugLabel: 'min-value');

  AppStore get store => widget.store;
  NotificationSettings? get _notifications =>
      store.data?.settings.notifications;

  @override
  void initState() {
    super.initState();
    final current = _notifications;
    if (current != null) {
      _time.text = current.timeOfDay;
      _minValue.text = (current.minValueCents / 100).toString();
    }
    _time.addListener(_changed);
    _minValue.addListener(_changed);
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
    if (current == null) return;
    final time = _time.text.trim();
    final cents = parseMoney(_minValue.text);
    final patch = <NotificationSettings Function(NotificationSettings)>[
      if (_timeValid(time) && time != current.timeOfDay)
        (n) => n.copyWith(timeOfDay: time),
      if (cents != null && cents >= 0 && cents != current.minValueCents)
        (n) => n.copyWith(minValueCents: cents),
    ];
    if (patch.isNotEmpty) {
      store.updateNotificationSettings((n) => patch.fold(n, (n, p) => p(n)));
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
    final n = settings.notifications;

    Widget title(String value) =>
        Semantics(header: true, child: Text(value, style: text.titleSmall));

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
          onChanged: (next) => store.updateNotificationSettings(
            (n) => n.copyWith(enabled: next),
          ),
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
          SwitchRow(
            title: 'Nudge me about locked credits',
            note:
                'Credits stuck behind an enrolment box. Off means silence '
                'about money you cannot yet spend.',
            label: 'Nudge me about locked credits',
            value: n.enrollmentReminder,
            onChanged: (next) => store.updateNotificationSettings(
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
      ],
    );
  }
}
