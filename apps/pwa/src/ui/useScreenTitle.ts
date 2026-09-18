import { createEffect } from 'solid-js'

export const APP_NAME = 'HelpMe Reward'

/**
 * Sets the document title for a screen (WCAG 2.4.2).
 *
 * A single-page app has one document, so without this every screen is
 * announced as "HelpMe Reward" and browser history is a list of identical
 * entries. The screen name leads so it is what a tab strip or a screen
 * reader's window list shows first.
 */
export function useScreenTitle(title: () => string): void {
  createEffect(() => {
    document.title = `${title()} · ${APP_NAME}`
  })
}
