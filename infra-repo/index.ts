/**
 * HelpMe Reward repository configuration.
 *
 * What is true of the repository regardless of environment: today, the
 * ruleset that makes the verify gate binding on `develop`. It is a separate
 * Pulumi project from `infra/` because that one has a stack per environment
 * and two stacks cannot both own one repository setting; this project has
 * exactly one stack, `repo`. Per-environment GitHub configuration (the
 * environment each stack deploys to and its variables) stays in `infra/`.
 *
 * The provider authenticates with `github:token` (secret config on a laptop,
 * a fine-grained token for this one repository) or `GITHUB_TOKEN` in the
 * environment (the workflow token in the verify gate, which can read but not
 * write). `pulumi preview` never calls GitHub unless refreshing, so the gate
 * needs no write access.
 */

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import * as github from '@pulumi/github'
import * as pulumi from '@pulumi/pulumi'
import { requiredChecks } from './verify-checks'

const config = new pulumi.Config('reward-app-repo')

const githubRepo = config.require('githubRepo')
if (!/^[\w.-]+\/[\w.-]+$/.test(githubRepo)) {
  throw new Error(`reward-app-repo:githubRepo must look like "owner/name", got "${githubRepo}"`)
}
const [, repoName] = githubRepo.split('/')

// ---------------------------------------------------------------------------
// The develop ruleset
// ---------------------------------------------------------------------------

/**
 * What makes the verify gate real rather than advisory. The ruleset requires
 * every job of `verify.yml` by name, and the names come from the file itself
 * (see `verify-checks.ts`), so a job that is added is required at once and a
 * job that is renamed is a visible diff here instead of a merge that quietly
 * stopped waiting for it. A pull request that renames a job is blocked until
 * `pulumi up` has run from that branch; runbook 01 §6 describes the flow.
 *
 * The pull-request-only rule for integration branches lives in an
 * organisation ruleset and is deliberately not repeated here.
 *
 * The ruleset predates this program: import it once with
 * `pulumi import github:index/repositoryRuleset:RepositoryRuleset develop-requires-verify <id>`
 * before the first `up`, or Pulumi creates a second one alongside it.
 */
const verifyWorkflow = readFileSync(join(__dirname, '..', '.github/workflows/verify.yml'), 'utf8')

new github.RepositoryRuleset('develop-requires-verify', {
  name: 'develop requires verify',
  repository: repoName,
  target: 'branch',
  enforcement: 'active',
  conditions: { refName: { includes: ['refs/heads/develop'], excludes: [] } },
  rules: {
    requiredStatusChecks: {
      strictRequiredStatusChecksPolicy: true,
      // 15368 is GitHub Actions' app id; without it any integration could
      // satisfy the check by posting a status with the same name.
      requiredChecks: requiredChecks(verifyWorkflow).map((context) => ({ context, integrationId: 15368 })),
    },
  },
})

export const repository = githubRepo
export const requiredContexts = requiredChecks(verifyWorkflow)
