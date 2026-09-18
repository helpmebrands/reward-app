# PWA interaction

How the reference PWA realises the [[design]] rules in a browser: the responsive shell, swipe rows, bottom sheets, forced colours and truncation.

Rows are rendered with `Index` rather than `For`, so a data change updates a row in place instead of rebuilding it and dropping keyboard focus.

## Responsive layout

Three breakpoints, each a set of layout token overrides in `apps/pwa/src/styles/tokens.css`; components keep reading the same names. Compact is the phone design as drawn and is pinned by [[pwa-tests#Accessibility tests#The phone layout does not move]].

| Breakpoint | Width | `--content-max` | `--rail-width` | `--screen-pad` | Navigation |
| --- | --- | --- | --- | --- | --- |
| Compact | under 600px | 402px | 0 | 20px | bottom tab bar |
| Medium | 600 to 1023px | 560px | 80px | 24px | rail, icons over labels |
| Expanded | 1024px and up | 720px | 200px | 28px | rail, labels beside icons |

From 600px the shell is a two-column grid: the rail on the leading edge of the viewport, full height, and the content column centred in what is left at its cap, still the only thing that scrolls. The tab bar is the same `<nav aria-label="Main">` with the same four buttons in the same DOM order; only its geometry changes, per Material's rule for this width. The snackbar and the nudge preview centre on the content column, not the viewport ([[pwa-tests#Accessibility tests#The rail and the centred column at wider widths]]).

Custom properties cannot drive a media query, so the two widths are repeated in the stylesheets that need them. A landscape phone under 600px keeps the compact layout with the short-viewport form in [[design#Accessibility]].

### What each screen does with the width

All of it is CSS grid on the phone markup, so the DOM and the reading order are the same at every width ([[pwa-tests#Accessibility tests#Reading order is the same at every width]]).

Route stylesheets are bundled before `base.css`, so a route rule that overrides a base utility such as `.stack` is written as a compound selector.

- **Today**: from 600px the overlap cards pair up. From 1024px the body is a two-column grid with the headline across both, the use-soon rows and captured rows in the first column and "Locked behind enrolment" beside them in the second.
- **Cards**: two cards across from 600px; from 1024px one per row with the verdict and tags beside the figures instead of under them.
- **Value**: the two totals were already side by side; the chart and the ranks grow with the column, and the visually-hidden table stays the accessible source.
- **Editors** (`.form-grid`): from 1024px short fields pair up two to a row in DOM order; panels, sections, buttons and text areas keep the whole row. Settings keeps one column, since its ladder table needs the width.

Screenshots at 768 and 1280px for review live in `apps/pwa/tests/e2e/screenshots/` ([[pwa-tests#Accessibility tests#Wider screens use the column]]).

## Swipe rows

Every credit row is reachable three ways: tap to open the sheet, swipe right to log the whole credit, swipe left to silence it. The swipe is an accelerator, never the only route, because a gesture nobody discovers is not a feature.

[[apps/pwa/src/ui/SwipeRow.tsx#SwipeRow]] implements Material's swipe-to-act with the behaviours that make it usable on a phone:

- **Direction locking.** The gesture only becomes a swipe once horizontal movement clearly beats vertical (10px), so a fast flick down the list never half-opens a row. Pointer capture happens only after the swipe is committed, so scrolling is never stolen.
- **Rubber-banding** past the 84px action width.
- **Commit on velocity or distance:** past 55% of the width, or a flick over 0.45 px/ms.
- **A visible resting state.** Releasing past the threshold parks the row open with the button exposed rather than firing. An irreversible action should not be one accidental flick away.
- Mouse input is ignored on purpose; a tap anywhere else closes an open row.

## Bottom sheets

[[apps/pwa/src/ui/Sheet.tsx#Sheet]] is a modal sheet in the shape the width calls for: a bottom sheet on a phone, a centred dialog from 600px, and for the credit sheet a side panel from 1024px. All three keep `role="dialog"`, `aria-modal`, Escape, the focus trap and focus return.

The presentation comes from [[apps/pwa/src/ui/useBreakpoint.ts#createBreakpoint]], which watches the two media queries the token sheet defines ([[interaction#Responsive layout]]).

- **Bottom** (compact): Material's sheet on Nocturne's surfaces. A drag handle that actually drags, dismissal by distance (110px) or by downward flick (0.5 px/ms), a scrim that closes on tap. The drag listens on the handle only: dragging from anywhere would fight the sheet's own scrolling, which matters because the credit sheet is taller than the screen.
- **Dialog** (medium, and the compare sheet at expanded): centred, at most 480px wide and 85% of the height, faded in. No handle, because there is nothing to drag.
- **Panel** (the credit sheet at expanded, `wide="panel"`): docked on the trailing edge, 380px wide, full height, slid in. There is no scrim and the container lets pointer events through, so the list stays usable and another row can be opened without closing it first; the shell keeps a column free for it (`body.has-panel`) so the list is narrower rather than covered. Focus is still trapped and Escape still closes, returning focus to the row that opened it.

Body scroll is locked while a sheet is open. Specified by [[pwa-tests#Accessibility tests#The sheet is a dialog from 600px]], [[pwa-tests#Accessibility tests#The sheet still drags on a phone]] and [[pwa-tests#Accessibility tests#The credit panel sits beside the list]].

## Forced colours

Under Windows High Contrast every background becomes the system Canvas, so `@media (forced-colors: active)` gives a border to every control that was drawn as a fill or a tonal step. Checked by [[pwa-tests#Accessibility tests#Every control keeps a boundary in forced colours]].

That is icon buttons, segments, tabs, swipe actions, the switch knob, catalogue entries, benefit links and overlap cards. Where a colour carries meaning, the status tags, the split bar, the chart bars and swatches, the current ladder rung and inline errors, `forced-color-adjust: none` keeps it. A pressed segment takes the system Highlight colours, since its tonal step is gone too.

Text is truncated with `.truncate` only where the full text is one tap away: a credit row's title opens the sheet that shows the whole name, a benefit link opens its editor, and the household filter's label sits over a native select. Subtitles, leak labels and screen titles wrap instead, so WCAG 1.4.12's spacing overrides lose nothing ([[pwa-tests#Accessibility tests#Text spacing overrides clip nothing]]).

Conformance is checked by axe at two levels ([[pwa-tests#Accessibility tests]]): in jsdom on every route as part of `npm test`, and in Chromium at four widths and both themes as the `a11y` job of the verify gate.
