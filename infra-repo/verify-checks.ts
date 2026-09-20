import { parse } from 'yaml'

/**
 * The status-check contexts the `develop` ruleset must require, derived from
 * the verify workflow itself.
 *
 * `ci.yml` calls `verify.yml` as a reusable workflow from a job whose id is
 * `verify`, so every job in it reports to GitHub as `verify / <job name>`.
 * Reading the list from the file means a new job is required the moment it
 * exists, and a renamed one shows up as a ruleset diff in `pulumi preview`
 * rather than as a merge that quietly stopped waiting for it.
 */
export function requiredChecks(workflowYaml: string): string[] {
  const doc = parse(workflowYaml) as { jobs?: Record<string, { name?: unknown }> } | null
  const jobs = doc?.jobs ?? {}
  const ids = Object.keys(jobs)
  if (ids.length === 0) {
    throw new Error('verify.yml declares no jobs; refusing to require nothing')
  }
  return ids.map((id) => {
    const name = jobs[id]?.name
    return `verify / ${typeof name === 'string' && name.trim() ? name : id}`
  })
}
