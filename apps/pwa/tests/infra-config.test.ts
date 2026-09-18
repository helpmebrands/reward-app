import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

// Guards the committed Pulumi configuration and the runbooks that quote it.
// The values here are a trust boundary (which repository may deploy) and a
// target (which project it deploys to); a drift is only noticed when a deploy
// is rejected at the auth step.

// The repository root: this suite lives in apps/pwa/tests.
const root = join(import.meta.dirname, '..', '..', '..')
const read = (path: string) => readFileSync(join(root, path), 'utf8')

function filesUnder(dir: string): string[] {
  return readdirSync(join(root, dir), { recursive: true, encoding: 'utf8' })
    .map((name) => join(dir, name))
    .filter((path) => !path.includes('node_modules') && statSync(join(root, path)).isFile())
}

describe('Pulumi project config', () => {
  // @lat: [[tests#Infrastructure config#Project is named reward-app]]
  it('is named reward-app', () => {
    expect(read('infra/Pulumi.yaml')).toMatch(/^name: reward-app$/m)
  })

  // @lat: [[tests#Infrastructure config#Project config declares no namespaced keys]]
  it('declares no namespaced keys at project level', () => {
    const configBlock = read('infra/Pulumi.yaml').split(/^config:\s*$/m)[1] ?? ''
    const namespaced = configBlock.match(/^ {2}[\w-]+:[\w-]+:/gm) ?? []
    expect(namespaced).toEqual([])
  })
})

describe('staging stack config', () => {
  const staging = () => read('infra/Pulumi.staging.yaml')

  // @lat: [[tests#Infrastructure config#Staging targets the decided project]]
  it('targets the helpme-reward-staging project', () => {
    expect(staging()).toMatch(/^\s+gcp:project:\s*helpme-reward-staging\s*$/m)
  })

  // @lat: [[tests#Infrastructure config#Staging maps its custom domain]]
  it('maps staging.helpmereward.com', () => {
    expect(staging()).toMatch(/^\s+reward-app:customDomain:\s*staging\.helpmereward\.com\s*$/m)
  })

  // @lat: [[tests#Infrastructure config#Staging trusts this repository]]
  it('trusts helpmebrands/reward-app to deploy', () => {
    expect(staging()).toMatch(/^\s+[\w-]+:githubRepo:\s*helpmebrands\/reward-app\s*$/m)
  })
})

describe('verify workflow', () => {
  // @lat: [[tests#Infrastructure config#Verify gate typechecks the Pulumi program]]
  it('typechecks the Pulumi program in its own job', () => {
    const verify = read('.github/workflows/verify.yml')
    const infraJob = verify.split(/^ {2}infra:\s*$/m)[1]
    expect(infraJob).toBeDefined()
    expect(infraJob).toContain('npm ci --workspace infra')
    expect(infraJob).toContain('npm run typecheck --workspace infra')
  })
})

describe('runbook README', () => {
  // @lat: [[tests#Infrastructure config#README records the staging environment]]
  it('records the staging project, region, stack, backend and URL', () => {
    const readme = read('docs/runbooks/README.md')
    for (const fact of [
      'helpme-reward-staging',
      'us-central1',
      'gs://helpme-reward-staging-pulumi-state',
      'https://reward-app-bduraqeztq-uc.a.run.app',
      'https://staging.helpmereward.com',
    ]) {
      expect(readme).toContain(fact)
    }
  })
})

describe('runbook 01', () => {
  // @lat: [[tests#Infrastructure config#Runbook names the real state backend]]
  it('logs Pulumi into the versioned state bucket', () => {
    expect(read('docs/runbooks/01-initial-deployment.md')).toContain(
      'pulumi login gs://helpme-reward-staging-pulumi-state',
    )
  })
})

describe('infra, runbooks, workflows and container files', () => {
  const files = [
    ...['infra', 'docs', '.github', 'apps/pwa/deploy'].flatMap(filesUnder),
    'apps/pwa/Dockerfile',
  ]

  // @lat: [[tests#Infrastructure config#No stale repository or project names]]
  it('never name the old repository or the misspelt project', () => {
    const stale = files.filter((path) => /oravecz\/cardvantage|helpme-rewards-/.test(read(path)))
    expect(stale).toEqual([])
  })

  // @lat: [[tests#Infrastructure config#No cardvantage in infrastructure names]]
  it('never use the pre-rebrand name cardvantage', () => {
    const stale = files.filter((path) => /cardvantage/i.test(read(path)))
    expect(stale).toEqual([])
  })
})

describe('monorepo layout', () => {
  // @lat: [[tests#Infrastructure config#Root package declares the workspaces]]
  it('declares apps/pwa and infra as npm workspaces at the root', () => {
    const pkg = JSON.parse(read('package.json')) as { workspaces?: string[] }
    expect(pkg.workspaces).toEqual(['apps/pwa', 'infra'])
  })

  // @lat: [[tests#Infrastructure config#The PWA lives in apps/pwa]]
  it('keeps the PWA package, Dockerfile and nginx config under apps/pwa', () => {
    const pwa = JSON.parse(read('apps/pwa/package.json')) as { name: string }
    expect(pwa.name).toBe('@helpmebrands/reward-app')
    expect(statSync(join(root, 'apps/pwa/Dockerfile')).isFile()).toBe(true)
    expect(statSync(join(root, 'apps/pwa/deploy/nginx.conf.template')).isFile()).toBe(true)
  })

  // @lat: [[tests#Infrastructure config#Workflows build the PWA image from its Dockerfile]]
  it('builds the image from apps/pwa/Dockerfile in verify and cd', () => {
    for (const workflow of ['verify.yml', 'cd.yml']) {
      const text = read(`.github/workflows/${workflow}`)
      expect(text, workflow).toContain('file: apps/pwa/Dockerfile')
    }
  })
})
