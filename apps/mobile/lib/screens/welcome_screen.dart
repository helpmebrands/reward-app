import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/nocturne_tokens.dart';
import '../widgets/brand_lockup.dart';
import '../widgets/screen_title.dart';
import 'welcome_hero.dart';
import 'welcome_heroes.dart';
import 'welcome_logo.dart';
import 'welcome_premium_mocks.dart';

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
    'All your rewards in one place',
    "See what's left on every card in your household and what to use first, "
        'so nothing slips by.',
    _upcomingRewards,
  ),
  WelcomeSlide(
    'Never miss another deadline',
    'Get a nudge before every credit expires, so no reward is left on the '
        "table. We'll remind you in time to use it, not after it's gone.",
    _timelyReminders,
  ),
  WelcomeSlide(
    'Get more from every card',
    'Premium marks credits used as you spend and points you to the card that '
        'earns the most, so you get more back with less effort.',
    _premiumFeatures,
  ),
];

Widget _upcomingRewards(BuildContext context) => const UpcomingRewardsHero();

Widget _timelyReminders(BuildContext context) => const TimelyRemindersHero();

Widget _premiumFeatures(BuildContext context) => const PremiumFeaturesHero();

/// The welcome slideshow. Skip, or Get started on the last slide, calls
/// [onDone]; the router then goes to sign-in.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.onDone,
    this.introLogo = false,
  });

  final VoidCallback onDone;

  /// Opens with the logo's hand-off from the native splash to the header
  /// ([WelcomeLogoLayers]), as the first launch does; a replay from "Learn
  /// more" opens on the lockup in place. Reduced motion skips it.
  final bool introLogo;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  final _pages = PageController();
  int _page = 0;

  final _stackKey = GlobalKey();
  final _lockupKey = GlobalKey();
  bool _logoChecked = false;
  AnimationController? _logo;
  Animation<double> _content = kAlwaysCompleteAnimation;
  Rect? _lockupRect;

  bool get _last => _page == welcomeSlides.length - 1;

  bool get _playing => _logo?.isCompleted == false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logoChecked) return;
    _logoChecked = true;
    if (!widget.introLogo || MediaQuery.disableAnimationsOf(context)) return;
    final logo = _logo =
        AnimationController(vsync: this, duration: welcomeLogoDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) setState(() {});
          });
    _content = CurvedAnimation(parent: logo, curve: const Interval(0.8, 1));
    // The move needs the header lockup's rect, known after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stack = _stackKey.currentContext!.findRenderObject()! as RenderBox;
      final lockup =
          _lockupKey.currentContext!.findRenderObject()! as RenderBox;
      // Too narrow for the icon beside the wordmark: place it with no move.
      if (lockup.size.width < BrandLockup.lockupSize.width) {
        logo.value = 1;
        return;
      }
      setState(() {
        _lockupRect =
            lockup.localToGlobal(Offset.zero, ancestor: stack) & lockup.size;
      });
      logo.forward();
    });
  }

  @override
  void dispose() {
    _logo?.dispose();
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
    final logo = _logo;
    return Scaffold(
      body: Stack(
        key: _stackKey,
        children: [
          IgnorePointer(
            ignoring: _playing,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s6),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                // Hidden while the layers stand in for it, but
                                // still the one "HelpMe reward" node.
                                child: Opacity(
                                  opacity: _playing ? 0 : 1,
                                  alwaysIncludeSemantics: true,
                                  child: BrandLockup(key: _lockupKey),
                                ),
                              ),
                            ),
                            FadeTransition(
                              opacity: _content,
                              child: TextButton(
                                key: const Key('welcome-skip'),
                                onPressed: widget.onDone,
                                child: const Text('Skip'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.s4),
                        Expanded(
                          child: FadeTransition(
                            opacity: _content,
                            child: PageView(
                              controller: _pages,
                              onPageChanged: (page) =>
                                  setState(() => _page = page),
                              children: [
                                for (final slide in welcomeSlides)
                                  LayoutBuilder(
                                    builder: (context, constraints) =>
                                        SingleChildScrollView(
                                          child: _HeroAboveText(
                                            height: constraints.maxHeight,
                                            hero: WelcomeHero(
                                              child: Builder(
                                                builder: slide.hero,
                                              ),
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
                                                const SizedBox(
                                                  height: Space.s3,
                                                ),
                                                Text(
                                                  slide.body,
                                                  style: text.bodyMedium
                                                      ?.copyWith(
                                                        color: tokens
                                                            .textSecondary,
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
                        ),
                        const SizedBox(height: Space.s6),
                        FadeTransition(
                          opacity: _content,
                          child: Column(
                            children: [
                              Semantics(
                                label:
                                    'Slide ${_page + 1} of ${welcomeSlides.length}',
                                child: ExcludeSemantics(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      for (
                                        var i = 0;
                                        i < welcomeSlides.length;
                                        i++
                                      )
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.all(
                                            Space.s1,
                                          ),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (logo != null && _playing)
            Positioned.fill(
              child: WelcomeLogoLayers(progress: logo, lockup: _lockupRect),
            ),
        ],
      ),
    );
  }
}

/// The share of the slide's height the hero takes when the text
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
