import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/nocturne_tokens.dart';
import '../widgets/brand_lockup.dart';
import '../widgets/screen_title.dart';
import 'welcome_hero.dart';

/// One slide of the welcome slideshow.
class WelcomeSlide {
  const WelcomeSlide(this.title, this.body, this.hero);

  final String title;
  final String body;

  /// Builds the product picture drawn in the slide's [WelcomeHero].
  final WidgetBuilder hero;
}

/// What the app is for, in three slides: shown before the first sign-in and
/// again from "Learn more" on the sign-in screen.
const welcomeSlides = [
  WelcomeSlide(
    'Upcoming rewards at a glance',
    'Every credit on every card in your household, in one list. The soonest '
        'to expire comes first, with the total you can still use at the top.',
    _placeholderHero,
  ),
  WelcomeSlide(
    'Timely reminders',
    'Each reminder is timed to its credit, from months ahead for a yearly '
        'credit to the last day for a monthly one. Alerts due on the same day '
        'arrive as one notification, led by the most money at risk.',
    _placeholderHero,
  ),
  WelcomeSlide(
    'Premium features',
    'Premium follows your card transactions through bank linking and marks '
        'credits used as you spend. AI insights show where another card would '
        'earn more points, where a card could be used better, and what you '
        'missed.',
    _placeholderHero,
  ),
];

/// Plain rows standing in for a slide's picture until its hero exists.
Widget _placeholderHero(BuildContext context) {
  final tokens = Theme.of(context).extension<NocturneTokens>()!;
  return Column(
    children: [
      for (var i = 0; i < 6; i++)
        Container(
          height: 56,
          margin: const EdgeInsets.only(bottom: Space.s4),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: tokens.surfaceLine),
          ),
        ),
    ],
  );
}

/// The welcome slideshow. Skip, or Get started on the last slide, calls
/// [onDone]; the router then goes to sign-in.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  int _page = 0;

  bool get _last => _page == welcomeSlides.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      widget.onDone();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NocturneTokens>()!;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(Space.s6),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: BrandLockup(),
                        ),
                      ),
                      TextButton(
                        key: const Key('welcome-skip'),
                        onPressed: widget.onDone,
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.s4),
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (page) => setState(() => _page = page),
                      children: [
                        for (final slide in welcomeSlides)
                          LayoutBuilder(
                            builder: (context, constraints) =>
                                SingleChildScrollView(
                                  child: _HeroAboveText(
                                    height: constraints.maxHeight,
                                    hero: WelcomeHero(
                                      child: Builder(builder: slide.hero),
                                    ),
                                    text: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ScreenTitle(
                                          label: slide.title,
                                          windowTitle: 'Welcome',
                                          style: text.headlineSmall,
                                        ),
                                        const SizedBox(height: Space.s3),
                                        Text(
                                          slide.body,
                                          style: text.bodyMedium?.copyWith(
                                            color: tokens.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.s6),
                  Semantics(
                    label: 'Slide ${_page + 1} of ${welcomeSlides.length}',
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < welcomeSlides.length; i++)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.all(Space.s1),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _page
                                    ? tokens.accent
                                    : tokens.surfaceLine,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('welcome-next'),
                      onPressed: _next,
                      child: Text(_last ? 'Get started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The share of the slide's height the hero panel takes when the text
/// leaves room for it.
const _heroShare = 0.55;

/// Below this height the hero is left out rather than drawn as a sliver.
const _minHero = 160.0;

/// A slide's hero above its text. The text takes its natural height first;
/// the hero gets what is left of [height], up to [_heroShare] of it, and is
/// left out (not painted, not in the semantics tree) when that is under
/// [_minHero]. Taller than [height] only when the text alone is, so the
/// scroll view around it scrolls.
class _HeroAboveText extends MultiChildRenderObjectWidget {
  _HeroAboveText({
    required this.height,
    required Widget hero,
    required Widget text,
  }) : super(children: [hero, text]);

  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeroAboveText(height);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeroAboveText renderObject,
  ) => renderObject.height = height;
}

class _SlotData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeroAboveText extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotData> {
  _RenderHeroAboveText(this._height);

  double _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  bool _heroShown = false;

  RenderBox get _hero => firstChild!;
  RenderBox get _text => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotData) child.parentData = _SlotData();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _text.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final heroHeight = math.min(
      _height * _heroShare,
      _height - _text.size.height - Space.s6,
    );
    _heroShown = heroHeight >= _minHero;
    _hero.layout(
      BoxConstraints.tight(Size(width, _heroShown ? heroHeight : 0)),
    );
    final top = _heroShown ? heroHeight + Space.s6 : 0.0;
    (_text.parentData! as _SlotData).offset = Offset(0, top);
    size = constraints.constrain(
      Size(width, math.max(_height, top + _text.size.height)),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_heroShown) context.paintChild(_hero, offset);
    context.paintChild(_text, offset + (_text.parentData! as _SlotData).offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_heroShown) visitor(_hero);
    visitor(_text);
  }
}
