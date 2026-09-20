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
  // @lat: [[infra-tests#Infrastructure config#Project is named reward-app]]
  it('is named reward-app', () => {
    expect(read('infra/Pulumi.yaml')).toMatch(/^name: reward-app$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Project config declares no namespaced keys]]
  // @lat: [[infra-tests#Infrastructure config#Project config declares the database tier]]
  it('declares the Cloud SQL tier with the smallest default', () => {
    const configBlock = read('infra/Pulumi.yaml').split(/^config:\s*$/m)[1] ?? ''
    expect(configBlock).toMatch(/^ {2}dbTier:\s*$/m)
    expect(configBlock).toContain('default: db-f1-micro')
  })

  it('declares no namespaced keys at project level', () => {
    const configBlock = read('infra/Pulumi.yaml').split(/^config:\s*$/m)[1] ?? ''
    const namespaced = configBlock.match(/^ {2}[\w-]+:[\w-]+:/gm) ?? []
    expect(namespaced).toEqual([])
  })
})

describe('staging stack config', () => {
  const staging = () => read('infra/Pulumi.staging.yaml')

  // @lat: [[infra-tests#Infrastructure config#Staging targets the decided project]]
  it('targets the helpme-reward-staging project', () => {
    expect(staging()).toMatch(/^\s+gcp:project:\s*helpme-reward-staging\s*$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Staging maps its custom domain]]
  it('maps staging.helpmereward.com', () => {
    expect(staging()).toMatch(/^\s+reward-app:customDomain:\s*staging\.helpmereward\.com\s*$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Staging uses the KMS secrets provider]]
  it('encrypts its secrets with the staging KMS key, not a passphrase', () => {
    expect(staging()).toMatch(
      /^secretsprovider: gcpkms:\/\/projects\/helpme-reward-staging\/locations\/us-central1\/keyRings\/pulumi\/cryptoKeys\/staging$/m,
    )
    expect(staging()).toMatch(/^encryptedkey: /m)
  })

  // @lat: [[infra-tests#Infrastructure config#Staging trusts this repository]]
  it('trusts helpmebrands/reward-app to deploy', () => {
    expect(staging()).toMatch(/^\s+[\w-]+:githubRepo:\s*helpmebrands\/reward-app\s*$/m)
  })
})

describe('verify workflow', () => {
  // @lat: [[infra-tests#Infrastructure config#Verify gate typechecks the Pulumi program]]
  it('typechecks the Pulumi program in its own job', () => {
    const verify = read('.github/workflows/verify.yml')
    const infraJob = verify.split(/^ {2}infra:\s*$/m)[1]
    expect(infraJob).toBeDefined()
    expect(infraJob).toContain('npm ci --workspace infra')
    expect(infraJob).toContain('npm run typecheck --workspace infra')
  })

  // @lat: [[infra-tests#Infrastructure config#Verify gate analyses and tests the Dart workspace]]
  // @lat: [[infra-tests#Infrastructure config#Verify gate previews the Pulumi program with keyless credentials]]
  it('previews the Pulumi program against the state bucket in the infra job', () => {
    const verify = read('.github/workflows/verify.yml')
    const infraJob = verify.split(/^ {2}infra:\s*$/m)[1]
    expect(infraJob).toContain('google-github-actions/auth@v2')
    expect(infraJob).toContain('pulumi login gs://helpme-reward-staging-pulumi-state')
    expect(infraJob).toContain('pulumi preview')
    // WIF needs an OIDC token; the calling workflow must grant it.
    expect(read('.github/workflows/ci.yml')).toMatch(/^ {2}id-token: write$/m)
    expect(read('.github/workflows/cd.yml')).toMatch(/^ {2}id-token: write$/m)
  })

  it('analyses and tests the Dart workspace in its own job', () => {
    const verify = read('.github/workflows/verify.yml')
    const dartJob = verify.split(/^ {2}dart:\s*$/m)[1]
    expect(dartJob).toBeDefined()
    expect(dartJob).toContain('dart pub get')
    expect(dartJob).toContain('dart analyze')
    expect(dartJob).toContain('dart test')
  })

  // @lat: [[infra-tests#Infrastructure config#Verify gate analyses and tests the Flutter app]]
  it('analyses and tests the Flutter app in its own job', () => {
    const verify = read('.github/workflows/verify.yml')
    const flutterJob = verify.split(/^ {2}flutter:\s*$/m)[1]
    expect(flutterJob).toBeDefined()
    expect(flutterJob).toContain('flutter analyze')
    expect(flutterJob).toContain('flutter test')
    expect(flutterJob).toContain('working-directory: apps/mobile')
  })

  // @lat: [[infra-tests#Infrastructure config#Verify gate builds and smoke-tests the api]]
  it('analyses, tests, builds and smoke-tests the api in its own job', () => {
    const verify = read('.github/workflows/verify.yml')
    const apiJob = verify.split(/^ {2}api:\s*$/m)[1]
    expect(apiJob).toBeDefined()
    expect(apiJob).toContain('working-directory: services/api')
    expect(apiJob).toContain('dart test')
    expect(apiJob).toContain('file: services/api/Dockerfile')
    expect(apiJob).toContain('/health')
    // Google's edge answers /healthz itself on run.app hosts; the route must
    // not use that path anywhere.
    expect(apiJob).not.toContain('/healthz')
  })

  // @lat: [[infra-tests#Infrastructure config#Api job tests against a Postgres service container]]
  it('gives the api job a Postgres service container and DATABASE_URL', () => {
    const verify = read('.github/workflows/verify.yml')
    const apiJob = verify.split(/^ {2}api:\s*$/m)[1]
    expect(apiJob).toContain('image: postgres:16')
    expect(apiJob).toContain('pg_isready')
    expect(apiJob).toContain('DATABASE_URL: postgres://')
    expect(apiJob).toContain('sslmode=disable')
  })
})

describe('api deploy workflow', () => {
  // @lat: [[infra-tests#Infrastructure config#Api CD workflow is path-filtered to the api and the domain]]
  it('runs cd-api.yml only for the api, the domain and itself, never for the PWA', () => {
    const cdApi = read('.github/workflows/cd-api.yml')
    const trigger = cdApi.split(/^jobs:\s*$/m)[0]
    expect(trigger).toMatch(/^\s+- ['"]?services\/api\/\*\*['"]?\s*$/m)
    expect(trigger).toMatch(/^\s+- ['"]?packages\/domain\/\*\*['"]?\s*$/m)
    expect(trigger).not.toContain('apps/pwa')
    const cd = read('.github/workflows/cd.yml')
    const pwaTrigger = cd.split(/^jobs:\s*$/m)[0]
    expect(pwaTrigger).toMatch(/^\s+paths-ignore:\s*$/m)
    expect(pwaTrigger).toMatch(/^\s+- ['"]?services\/api\/\*\*['"]?\s*$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Api CD builds, migrates, deploys and smoke-tests]]
  it('builds the api image, runs the migration job, deploys by digest and smoke-tests', () => {
    const cdApi = read('.github/workflows/cd-api.yml')
    expect(cdApi).toContain('file: services/api/Dockerfile')
    expect(cdApi).toContain('gcloud run jobs update ${{ vars.API_MIGRATION_JOB }}')
    expect(cdApi).toContain('gcloud run jobs execute ${{ vars.API_MIGRATION_JOB }}')
    expect(cdApi).toContain('service: ${{ vars.API_CLOUD_RUN_SERVICE }}')
    expect(cdApi).toMatch(/reward-api@\$\{\{ steps\.build\.outputs\.digest \}\}/)
    expect(cdApi).toContain('/health')
    expect(cdApi).not.toContain('/healthz')
    expect(cdApi).toContain('Mars/Olympus_Mons')
  })

  // @lat: [[infra-tests#Infrastructure config#Api image carries the migrator and the migrations]]
  it('compiles the migrator into the api image beside the migrations', () => {
    const dockerfile = read('services/api/Dockerfile')
    expect(dockerfile).toContain('dart compile exe services/api/bin/migrate.dart -o /app/migrate')
    expect(dockerfile).toMatch(/^COPY --from=build \/app\/migrate \/migrate$/m)
    expect(dockerfile).toMatch(/^COPY --from=build \/app\/services\/api\/migrations \/migrations$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Api service runs on the gen2 execution environment]]
  it('runs the api service and job on the second-generation execution environment', () => {
    const program = read('infra/index.ts')
    const api = program.split('// The api service and its migration job')[1] ?? ''
    expect(api.match(/executionEnvironment: 'EXECUTION_ENVIRONMENT_GEN2'/g)).toHaveLength(2)
  })

  // @lat: [[infra-tests#Infrastructure config#Stack outputs name the api service and job]]
  it('exports the api service, its URL and the migration job from the stack', () => {
    const program = read('infra/index.ts')
    expect(program).toMatch(/^export const apiCloudRunService = /m)
    expect(program).toMatch(/^export const apiServiceUrl = /m)
    expect(program).toMatch(/^export const apiMigrationJob = /m)
  })
})

describe('runbook README', () => {
  // @lat: [[infra-tests#Infrastructure config#README records the staging environment]]
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

describe('runbooks for two services', () => {
  // @lat: [[infra-tests#Infrastructure config#README records both services and the database]]
  it('records the api service, its job, the database and the secret in the README table', () => {
    const readme = read('docs/runbooks/README.md')
    for (const fact of [
      '`reward-app`',
      '`reward-api`',
      '`reward-api-migrate`',
      '`reward-api-db-staging`',
      '`reward-api-database-url-staging`',
      'https://reward-api-bduraqeztq-uc.a.run.app',
      '06 — Database',
      '07 — Mobile release',
    ]) {
      expect(readme).toContain(fact)
    }
    expect(readme).not.toContain('There is no database and no backend')
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 01 bootstraps the KMS secrets provider]]
  it('has runbook 01 create the KMS key and move the stack to it, not an empty passphrase', () => {
    const rb = read('docs/runbooks/01-initial-deployment.md')
    expect(rb).toContain('gcloud kms keyrings create')
    expect(rb).toContain('pulumi stack change-secrets-provider')
    expect(rb).toContain('API_CLOUD_RUN_SERVICE')
    expect(rb).toContain('API_MIGRATION_JOB')
    expect(rb).not.toContain('PULUMI_CONFIG_PASSPHRASE=""')
  })

  // @lat: [[infra-tests#Infrastructure config#Runbooks 06 and 07 exist with their rehearsed commands]]
  it('has a database runbook with migrations, backups, restore and local access, and a mobile release runbook', () => {
    const db = read('docs/runbooks/06-database.md')
    expect(db).toContain('gcloud run jobs execute')
    expect(db).toContain('gcloud sql backups create')
    expect(db).toContain('gcloud sql backups restore')
    expect(db).toContain('cloud-sql-proxy')
    expect(db).toContain('schema_migrations')
    const mobile = read('docs/runbooks/07-mobile-release.md')
    expect(mobile).toContain('flutter build')
    expect(mobile).toContain('TestFlight')
    expect(mobile).toContain('internal')
  })
})

describe('runbook 01', () => {
  // @lat: [[infra-tests#Infrastructure config#Runbook names the real state backend]]
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

  // @lat: [[infra-tests#Infrastructure config#No stale repository or project names]]
  it('never name the old repository or the misspelt project', () => {
    const stale = files.filter((path) => /oravecz\/cardvantage|helpme-rewards-/.test(read(path)))
    expect(stale).toEqual([])
  })

  // @lat: [[infra-tests#Infrastructure config#No cardvantage in infrastructure names]]
  it('never use the pre-rebrand name cardvantage', () => {
    const stale = files.filter((path) => /cardvantage/i.test(read(path)))
    expect(stale).toEqual([])
  })
})

describe('monorepo layout', () => {
  // @lat: [[infra-tests#Infrastructure config#Root package declares the workspaces]]
  it('declares apps/pwa and infra as npm workspaces at the root', () => {
    const pkg = JSON.parse(read('package.json')) as { workspaces?: string[] }
    expect(pkg.workspaces).toEqual(['apps/pwa', 'infra'])
  })

  // @lat: [[infra-tests#Infrastructure config#Root pubspec declares the pub workspace]]
  it('declares packages/domain in the pub workspace at the root', () => {
    const pubspec = read('pubspec.yaml')
    const workspace = pubspec.split(/^workspace:\s*$/m)[1] ?? ''
    expect(workspace).toMatch(/^\s+- packages\/domain\s*$/m)
    expect(workspace).toMatch(/^\s+- apps\/mobile\s*$/m)
    expect(workspace).toMatch(/^\s+- services\/api\s*$/m)
    expect(read('packages/domain/pubspec.yaml')).toMatch(/^resolution: workspace$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#The PWA lives in apps/pwa]]
  it('keeps the PWA package, Dockerfile and nginx config under apps/pwa', () => {
    const pwa = JSON.parse(read('apps/pwa/package.json')) as { name: string }
    expect(pwa.name).toBe('@helpmebrands/reward-app')
    expect(statSync(join(root, 'apps/pwa/Dockerfile')).isFile()).toBe(true)
    expect(statSync(join(root, 'apps/pwa/deploy/nginx.conf.template')).isFile()).toBe(true)
  })

  // @lat: [[infra-tests#Infrastructure config#Workflows build the PWA image from its Dockerfile]]
  it('builds the image from apps/pwa/Dockerfile in verify and cd', () => {
    for (const workflow of ['verify.yml', 'cd.yml']) {
      const text = read(`.github/workflows/${workflow}`)
      expect(text, workflow).toContain('file: apps/pwa/Dockerfile')
    }
  })
})

describe('billing budget', () => {
  // @lat: [[infra-tests#Infrastructure config#Project config declares the budget]]
  it('declares billingAccount and budgetAmount at project level', () => {
    const configBlock = read('infra/Pulumi.yaml').split(/^config:\s*$/m)[1] ?? ''
    expect(configBlock).toMatch(/^ {2}billingAccount:\s*$/m)
    expect(configBlock).toMatch(/^ {2}budgetAmount:\s*\n(?: {4}.*\n)*? {4}default: \d+$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Staging keeps the billing account secret]]
  it('carries the staging billing account only as a secret', () => {
    const staging = read('infra/Pulumi.staging.yaml')
    expect(staging).toMatch(/^\s+reward-app:billingAccount:\s*\n\s+secure: /m)
    expect(staging).not.toMatch(/^\s+reward-app:billingAccount:\s*[\w-]+\s*$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Program declares the budget]]
  it('enables the budget API and declares one budget filtered to the project', () => {
    const program = read('infra/index.ts')
    expect(program).toContain("'billingbudgets.googleapis.com'")
    expect(program).toMatch(/new gcp\.billing\.Budget\(/)
    expect(program).toMatch(/projects\/\$\{[^}]*number[^}]*\}/i)
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 03 points at the declared budget]]
  it('is described in runbook 03 instead of left to the operator', () => {
    const costs = read('docs/runbooks/03-infrastructure-change.md').split(/^## Costs\s*$/m)[1] ?? ''
    expect(costs).toContain('budgetAmount')
    expect(costs).not.toMatch(/Set a budget alert on the project anyway/)
  })
})
