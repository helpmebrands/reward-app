import { describe, expect, it } from 'vitest'
import { requiredChecks } from '../../../infra/verify-checks'

// The develop ruleset requires status checks by name. ci.yml calls verify.yml
// from a job with id `verify`, so every job in verify.yml reports as
// `verify / <job name>`. Deriving the list from the workflow means adding a
// job makes it required, and renaming one is a visible ruleset diff.

const fixture = `
name: Verify
on:
  workflow_call:
jobs:
  verify:
    name: Lint, typecheck, test, build
    runs-on: ubuntu-latest
  a11y:
    name: Accessibility gate
    needs: verify
    runs-on: ubuntu-latest
  unnamed:
    runs-on: ubuntu-latest
`

describe('requiredChecks', () => {
  // @lat: [[infra-tests#Infrastructure config#Required checks derive from verify.yml]]
  it('maps every job to its "verify / <name>" context, falling back to the job id', () => {
    expect(requiredChecks(fixture)).toEqual([
      'verify / Lint, typecheck, test, build',
      'verify / Accessibility gate',
      'verify / unnamed',
    ])
  })

  it('rejects a workflow with no jobs rather than requiring nothing', () => {
    expect(() => requiredChecks('name: Empty\non: push\n')).toThrow(/no jobs/)
  })
})
