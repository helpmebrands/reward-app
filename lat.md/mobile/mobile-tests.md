# Mobile tests

What the Flutter widget suites in `apps/mobile/test/` guard, run by the `flutter` job of the verify gate ([[deployment#Pipeline]]).

## Theme

`theme_test.dart` pins the theme to the Nocturne tokens so a re-theme is a deliberate token change rather than drift ([[mobile-architecture#Theme]]).

### Both themes carry the Nocturne token colours

Each theme's primary, surface, on-surface and scaffold colours are the `tokens.css` values for its mode, and each carries its token set as the extension.

Dark: `#9184d9`, `#232532`, `#e9e9ed`, `#161826`. Light: `#5d5294`, `#ffffff`, `#232532`, `#f3f5fe`.

### The app follows the platform brightness

With the platform reporting dark, the running app resolves the dark accent as primary and the dark "use soon" ground from the extension, so the system setting is what picks the theme.
