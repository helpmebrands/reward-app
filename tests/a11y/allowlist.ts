/**
 * Known accessibility failures, by axe rule id.
 *
 * Epic #21 lands its fixes one sub-issue at a time. Recording the failures the
 * audit already found here keeps both gates green from the first day, and each
 * sub-issue tightens the gate by deleting its own entries. Every entry names
 * the sub-issue that removes it; an entry without one is a bug, not a policy.
 *
 * Both suites read this file so the allowlist lives in exactly one place.
 */

/** Rules disabled in the jsdom component suite (`tests/a11y`). */
export const COMPONENT_ALLOWLIST: readonly string[] = []

/** Rules disabled in the Playwright suite (`tests/e2e`) against the built app. */
export const E2E_ALLOWLIST: readonly string[] = []
