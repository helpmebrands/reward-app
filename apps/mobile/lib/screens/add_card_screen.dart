import 'package:domain/domain.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:go_router/go_router.dart';

import '../logic/app_store.dart';
import '../logic/ui_state.dart';
import '../shell/router.dart';
import '../shell/width_class.dart';
import '../theme/nocturne_tokens.dart';
import '../widgets/field.dart';
import '../widgets/screen_title.dart';
import '../widgets/snackbar_host.dart';
import 'card_editor_screen.dart' show KindChoice;

/// Add a card, in two steps: pick the product, then say whose it is and when
/// the cardmember year turns over.
///
/// The holder is asked for rather than inferred, because the whole app turns
/// on telling two identical Platinums apart. Save is never disabled: an
/// invalid submit shows the errors and focuses the first, since a disabled
/// button never says why. Back with a draft asks first.
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({
    super.key,
    required this.store,
    this.ui,
    this.initialTemplate,
  });

  /// A template already picked, which opens the screen on step two. For the
  /// Widget Preview; the route always starts on the catalogue.
  final CardTemplate? initialTemplate;

  final AppStore store;
  final UiState? ui;

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  CardTemplate? _picked;
  bool _submitted = false;
  CardKind _kind = CardKind.personal;

  late final String _initialHolder;
  late final String _today;
  final _issuer = TextEditingController();
  final _product = TextEditingController();
  final _holder = TextEditingController();
  final _anniversary = TextEditingController();
  final _nickname = TextEditingController();
  final _issuerFocus = FocusNode(debugLabel: 'issuer');
  final _productFocus = FocusNode(debugLabel: 'product');
  final _holderFocus = FocusNode(debugLabel: 'holder');
  final _anniversaryFocus = FocusNode(debugLabel: 'anniversary');
  final _nicknameFocus = FocusNode(debugLabel: 'nickname');

  AppStore get store => widget.store;
  bool get _isBlank => _picked?.id == 'blank';

  @override
  void initState() {
    super.initState();
    final data = store.data;
    _initialHolder = data == null ? '' : (holders(data).firstOrNull ?? '');
    _today = store.today;
    final initial = widget.initialTemplate;
    if (initial != null) _apply(initial);
    _holder.text = _initialHolder;
    _anniversary.text = _today;
    for (final c in [_issuer, _product, _holder, _anniversary, _nickname]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_issuer, _product, _holder, _anniversary, _nickname]) {
      c.dispose();
    }
    for (final f in [
      _issuerFocus,
      _productFocus,
      _holderFocus,
      _anniversaryFocus,
      _nicknameFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  String? get _issuerError => _isBlank
      ? requiredError(_issuer.text, 'Enter who issues the card.')
      : null;
  String? get _productError => _isBlank
      ? requiredError(_product.text, 'Enter the name of the card.')
      : null;
  String? get _holderError =>
      requiredError(_holder.text, 'Enter whose card this is.');
  String? get _anniversaryError => anniversaryError(_anniversary.text);

  /// Anything typed since the template was picked.
  bool get _dirty =>
      _holder.text != _initialHolder ||
      _anniversary.text != _today ||
      _nickname.text.isNotEmpty ||
      (_isBlank && (_issuer.text.isNotEmpty || _product.text.isNotEmpty));

  void _pick(CardTemplate template) {
    setState(() => _apply(template));
  }

  void _apply(CardTemplate template) {
    _picked = template;
    _submitted = false;
    _kind = template.kind;
    _issuer.text = template.id == 'blank' ? '' : template.issuer;
    _product.text = template.id == 'blank' ? '' : template.product;
  }

  void _leave() => context.go(Paths.cards);

  /// Back: to the catalogue when nothing was typed, after asking otherwise.
  Future<void> _back() async {
    if (_picked == null) {
      _leave();
      return;
    }
    if (!_dirty) {
      setState(() => _picked = null);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this card?'),
        content: const Text('What you typed here will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _leave();
  }

  Future<void> _save() async {
    final template = _picked;
    if (template == null) return;
    // Pressing Save with an invalid form shows the errors rather than doing
    // nothing: a disabled button never says why.
    setState(() => _submitted = true);
    final firstInvalid = [
      (_issuerError, _issuerFocus),
      (_productError, _productFocus),
      (_holderError, _holderFocus),
      (_anniversaryError, _anniversaryFocus),
    ].where((e) => e.$1 != null).firstOrNull;
    if (firstInvalid != null) {
      firstInvalid.$2.requestFocus();
      return;
    }

    final nickname = _nickname.text.trim();
    final card = await store.addCardFromTemplate(
      template,
      holder: _holder.text.trim(),
      anniversaryOn: _anniversary.text,
      nickname: nickname.isEmpty ? null : nickname,
      issuer: _isBlank ? _issuer.text.trim() : null,
      product: _isBlank ? _product.text.trim() : null,
      kind: _kind,
    );
    final count = template.benefits.length;
    widget.ui?.snackbar.show(
      count > 0
          ? 'Added with $count credit${count == 1 ? '' : 's'}. Check the '
                'terms — issuers change them.'
          : 'Card added. Add its credits next.',
    );
    if (mounted) context.go(cardPath(card.id));
  }

  Future<void> _pickDate() async {
    final parsed = DateTime.tryParse(_anniversary.text);
    final chosen = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (chosen != null) {
      _anniversary.text = todayIso(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    // A full-screen route sits outside the shell, so it computes the width
    // class itself and hands it down the way the shell does.
    final widthClass = WidthClass.forWidth(MediaQuery.sizeOf(context).width);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: _back,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScreenTitle(
                label: picked == null ? 'Add a card' : 'Card details',
              ),
              Text(
                picked == null ? '1 of 2' : '2 of 2',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: _hosted(
            WidthClassScope(
              widthClass: widthClass,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: widthClass.column),
                  child: Builder(
                    builder: (context) =>
                        picked == null ? _catalogue(context) : _form(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A full-screen route sits above the shell's snackbar host, so it hosts
  /// the snackbar itself.
  Widget _hosted(Widget child) {
    final snackbar = widget.ui?.snackbar;
    return snackbar == null
        ? child
        : SnackbarHost(snackbar: snackbar, child: child);
  }

  Widget _catalogue(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final widthClass = WidthClass.of(context);
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);
    return ListView(
      padding: EdgeInsets.all(widthClass.padding),
      children: [
        Text(
          'Pick a card and its credits arrive pre-filled, including which ones '
          'need enrolment. Everything stays editable — treat the catalogue as '
          'a starting point, not gospel.',
          style: note,
        ),
        const SizedBox(height: Space.s6),
        for (final template in cardTemplates)
          if (template.id != 'blank')
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s3),
              child: _TemplateTile(
                key: ValueKey('template-${template.id}'),
                template: template,
                onTap: () => _pick(template),
              ),
            ),
        OutlinedButton.icon(
          onPressed: () => _pick(findTemplate('blank')!),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Set one up by hand'),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final widthClass = WidthClass.of(context);
    final template = _picked!;
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);
    final data = store.data;
    final known = data == null ? const <String>[] : holders(data);

    Widget field(
      String key,
      String label, {
      String? hint,
      required String? error,
      required TextEditingController controller,
      required FocusNode focusNode,
      bool required = false,
      TextInputType? keyboardType,
      Widget? suffix,
      Iterable<String>? suggestions,
    }) => Field(
      label: label,
      hint: hint,
      error: error,
      required: required,
      submitted: _submitted,
      focusNode: focusNode,
      builder: (context, control) => TextField(
        key: Key(key),
        controller: controller,
        focusNode: control.focusNode,
        keyboardType: keyboardType,
        decoration: control.decoration.copyWith(suffixIcon: suffix),
      ),
    );

    // Short fields pair two to a row from expanded; the panel, the note and
    // the button keep the whole row.
    final short = <Widget>[
      if (_isBlank) ...[
        field(
          'field-issuer',
          'Issuer',
          required: true,
          error: _issuerError,
          controller: _issuer,
          focusNode: _issuerFocus,
        ),
        field(
          'field-product',
          'Card',
          required: true,
          error: _productError,
          controller: _product,
          focusNode: _productFocus,
        ),
      ],
      field(
        'field-holder',
        'Whose card is it?',
        required: true,
        hint:
            'Two people holding the same product is the case this app exists '
            'for — the name is how their credits stay apart.'
            '${known.isEmpty ? '' : ' Known: ${known.join(', ')}.'}',
        error: _holderError,
        controller: _holder,
        focusNode: _holderFocus,
      ),
      field(
        'field-anniversary',
        'Account opened / renews on',
        required: true,
        hint:
            'Anniversary-based credits run from this date, not from 1 January. '
            'Getting it wrong is the commonest way a credit is lost.',
        error: _anniversaryError,
        controller: _anniversary,
        focusNode: _anniversaryFocus,
        keyboardType: TextInputType.datetime,
        suffix: IconButton(
          tooltip: 'Pick a date',
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          onPressed: _pickDate,
        ),
      ),
      field(
        'field-nickname',
        'Nickname (optional)',
        error: null,
        controller: _nickname,
        focusNode: _nicknameFocus,
      ),
      KindChoice(
        kind: _kind,
        onChanged: (kind) => setState(() => _kind = kind),
      ),
    ];

    final Widget fields = widthClass == WidthClass.expanded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < short.length; i += 2) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: short[i]),
                    const SizedBox(width: Space.s8),
                    Expanded(
                      child: i + 1 < short.length
                          ? short[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s6),
              ],
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final f in short) ...[f, const SizedBox(height: Space.s6)],
            ],
          );

    return ListView(
      padding: EdgeInsets.all(widthClass.padding),
      children: [
        if (!_isBlank)
          Container(
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
              border: Border.all(color: tokens.surfaceLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.issuer, style: note),
                Text(template.product, style: text.titleMedium),
                Text(
                  '${template.benefits.length} credits worth '
                  '${formatMoney(templateAnnualValueCents(template))} a year '
                  'against a ${formatMoney(template.annualFeeCents)} fee.',
                  style: note,
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.s6),
        Text('Fields marked * are required.', style: note),
        const SizedBox(height: Space.s4),
        fields,
        const SizedBox(height: Space.s6),
        OutlinedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Add this card'),
        ),
      ],
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({super.key, required this.template, required this.onTap});

  final CardTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    final note = text.bodySmall?.copyWith(color: tokens.textSecondary);
    final enrol = templateEnrollmentNames(template).length;
    return Material(
      color: tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        side: BorderSide(color: tokens.surfaceLine),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.issuer, style: note),
                    Text(template.product, style: text.titleSmall),
                    const SizedBox(height: Space.s2),
                    Wrap(
                      spacing: Space.s3,
                      children: [
                        Text(
                          '${formatMoney(template.annualFeeCents)} fee',
                          style: text.bodySmall,
                        ),
                        Text(
                          '${formatMoney(templateAnnualValueCents(template))} '
                          'in credits',
                          style: text.bodySmall?.copyWith(
                            color: tokens.accentRamp[300],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${template.benefits.length} credits'
                      '${enrol > 0 ? ' · $enrol need enrolment' : ''}',
                      style: note,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
