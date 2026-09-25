import 'package:flutter/material.dart';

import '../theme/nocturne_tokens.dart';
import '../widgets/brand_logo.dart';
import '../widgets/screen_title.dart';

/// One slide of the welcome slideshow.
class WelcomeSlide {
  const WelcomeSlide(this.icon, this.title, this.body);

  /// The slide's picture; null draws the stacked brand logo.
  final IconData? icon;
  final String title;
  final String body;
}

/// What the app is for, in three slides: shown before the first sign-in and
/// again from "Learn more" on the sign-in screen.
const welcomeSlides = [
  WelcomeSlide(
    null,
    'Every credit, before it lapses',
    'Premium cards pay back in monthly, quarterly and yearly credits. '
        'HelpMe Reward tracks each one and shows what is about to expire.',
  ),
  WelcomeSlide(
    Icons.people_outline,
    'One household, every card',
    'Share the household with the people you hold cards with. Two of the '
        'same card stay apart, and one purchase is never counted twice.',
  ),
  WelcomeSlide(
    Icons.notifications_active_outlined,
    'Reminders that lead with the money',
    'A nudge names the largest credit at risk and when it goes, so you '
        'spend it rather than lose it.',
  ),
];

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
                      // Expanded, so at a large text size the name wraps
                      // instead of pushing Skip off the right edge.
                      Expanded(
                        child: ScreenTitle(
                          label: 'Welcome',
                          text: 'HelpMe Reward',
                          style: text.titleSmall,
                        ),
                      ),
                      TextButton(
                        key: const Key('welcome-skip'),
                        onPressed: widget.onDone,
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (page) => setState(() => _page = page),
                      children: [
                        for (final slide in welcomeSlides)
                          SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: Space.s12),
                                if (slide.icon case final icon?)
                                  Icon(icon, size: 56, color: tokens.accent)
                                else
                                  const BrandLogo.stacked(),
                                const SizedBox(height: Space.s6),
                                Semantics(
                                  header: true,
                                  headingLevel: 2,
                                  child: Text(
                                    slide.title,
                                    textAlign: TextAlign.center,
                                    style: text.headlineSmall,
                                  ),
                                ),
                                const SizedBox(height: Space.s3),
                                Text(
                                  slide.body,
                                  textAlign: TextAlign.center,
                                  style: text.bodyMedium?.copyWith(
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
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
