import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
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
    expect(infraJob).toMatch(/uses: google-github-actions\/auth@v\d+/)
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

  // @lat: [[infra-tests#Infrastructure config#Flutter version is pinned once with FVM]]
  it('pins the Flutter version in .fvmrc and every workflow reads it from there', () => {
    const fvmrc = JSON.parse(read('.fvmrc')) as { flutter?: string }
    expect(fvmrc.flutter).toMatch(/^\d+\.\d+\.\d+$/)
    for (const file of ['.github/workflows/verify.yml', '.github/workflows/release-mobile.yml']) {
      const workflow = read(file)
      const setups = workflow.match(/uses: subosito\/flutter-action@v2/g) ?? []
      expect(setups.length, file).toBeGreaterThan(0)
      const fromFile = workflow.match(/flutter-version-file: \.fvmrc/g) ?? []
      expect(fromFile.length, file).toBe(setups.length)
      expect(workflow, file).not.toMatch(/flutter-version:/)
    }
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

describe('runbook 08 sign-in providers', () => {
  const runbook08 = () => read('docs/runbooks/08-sign-in-providers.md')

  // @lat: [[infra-tests#Infrastructure config#Runbook 08 lists the sign-in hand steps]]
  it('is indexed and walks through the Google and Apple hand steps', () => {
    expect(read('docs/runbooks/README.md')).toContain('(08-sign-in-providers.md)')
    const runbook = runbook08()
    expect(runbook).toMatch(/^## Google$/m)
    expect(runbook).toMatch(/^## Apple$/m)
    expect(runbook).toContain('https://helpme-reward-staging.firebaseapp.com/__/auth/handler')
    expect(runbook).toContain('Sign in with Apple')
    expect(runbook).toMatch(/provisioning profile/i)
    expect(runbook).toContain('appleSignInConfig')
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 08 stores credentials as stack secrets]]
  it('stores each credential as stack config, the secret ones with --secret', () => {
    const runbook = runbook08()
    for (const key of ['googleOAuthClientSecret', 'appleServicesKey']) {
      expect(runbook, key).toMatch(new RegExp(`pulumi config set --secret reward-app:${key}`))
    }
    for (const key of ['googleOAuthClientId', 'appleServicesId', 'appleKeyId']) {
      expect(runbook, key).toMatch(new RegExp(`pulumi config set reward-app:${key}`))
    }
    expect(runbook).not.toMatch(/gcloud secrets versions add/)
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
    expect(pkg.workspaces).toEqual(['apps/pwa', 'infra', 'infra-repo'])
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

describe('develop ruleset', () => {
  // @lat: [[infra-tests#Infrastructure config#Program declares the develop ruleset]]
  it('declares the ruleset in the repo-level project with checks derived from verify.yml', () => {
    const program = read('infra-repo/index.ts')
    expect(program).toMatch(/from '@pulumi\/github'/)
    expect(program).toMatch(/new github\.RepositoryRuleset\(/)
    expect(program).toMatch(/requiredChecks\(/)
    expect(program).toContain("'.github/workflows/verify.yml'")
    expect(read('infra/index.ts')).not.toMatch(/RepositoryRuleset/)
  })

  // @lat: [[infra-tests#Infrastructure config#Repo-level project has its own stack]]
  it('is a separate Pulumi project with one stack named repo', () => {
    expect(read('infra-repo/Pulumi.yaml')).toMatch(/^name: reward-app-repo$/m)
    const repo = read('infra-repo/Pulumi.repo.yaml')
    expect(repo).toMatch(/^\s+github:owner:\s*helpmebrands\s*$/m)
    expect(repo).toMatch(/^secretsprovider: gcpkms:\/\//m)
    expect(repo).not.toMatch(/^\s+github:token:[ \t]*\S/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Staging names the GitHub owner]]
  it('names the GitHub owner per stack and keeps the token out of plain text', () => {
    const staging = read('infra/Pulumi.staging.yaml')
    expect(staging).toMatch(/^\s+github:owner:\s*helpmebrands\s*$/m)
    expect(staging).not.toMatch(/^\s+github:token:[ \t]*\S/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Verify gate previews GitHub resources with the workflow token]]
  it('gives the preview step the workflow token for the GitHub provider', () => {
    const step = read('.github/workflows/verify.yml').split('Preview against staging')[1] ?? ''
    expect(step).toMatch(/GITHUB_TOKEN:\s*\$\{\{\s*github\.token\s*\}\}/)
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 01 describes the ruleset, not the settings UI]]
  it('is described in runbook 01 as stack-managed', () => {
    const section = read('docs/runbooks/01-initial-deployment.md').split(/^## 6\. /m)[1] ?? ''
    expect(section).not.toContain('Settings → Branches')
    expect(section).toContain('RepositoryRuleset')
    expect(section).toContain('pulumi import')
  })
})

describe('GitHub environment per stack', () => {
  const workflows = () =>
    ['verify.yml', 'cd.yml', 'cd-api.yml', 'release-mobile.yml'].map((name) =>
      read(`.github/workflows/${name}`),
    )
  // Build-time PWA variables are optional and set by hand (runbook 01 §5).
  const optional = new Set(['VITE_VAPID_PUBLIC_KEY', 'VITE_PUSH_API'])

  // @lat: [[infra-tests#Infrastructure config#Every workflow variable is declared on the environment]]
  it('declares every vars.* the workflows read as an environment variable', () => {
    const referenced = new Set(
      workflows()
        .flatMap((text) => [...text.matchAll(/vars\.([A-Z_]+)/g)].map((m) => m[1] ?? ''))
        .filter((v) => !optional.has(v)),
    )
    for (const name of [
      'API_CLOUD_RUN_SERVICE',
      'API_MIGRATION_JOB',
      'ARTIFACT_REPO',
      'CLOUD_RUN_SERVICE',
      'DEPLOY_SERVICE_ACCOUNT',
      'GCP_PROJECT_ID',
      'GCP_REGION',
      'WIF_PROVIDER',
      'PLAY_SERVICE_ACCOUNT',
    ]) {
      expect(referenced, name).toContain(name)
    }
    const program = read('infra/index.ts')
    expect(program).toMatch(/new github\.RepositoryEnvironment\(/)
    const declared = program.split('const environmentVariables')[1]?.split('\n}')[0] ?? ''
    const signing = program.split('const signingSecrets')[1]?.split(']')[0] ?? ''
    for (const name of referenced) {
      if (name.startsWith('SECRET_')) {
        const base = name.slice('SECRET_'.length).toLowerCase().replace(/_/g, '-')
        expect(signing, name).toContain(`'${base}'`)
      } else {
        expect(declared, name).toMatch(new RegExp(`^\\s+${name}:`, 'm'))
      }
    }
  })

  // @lat: [[infra-tests#Infrastructure config#Workflows run in the stack's environment]]
  it('runs the deploy and preview jobs in the staging environment', () => {
    for (const name of ['cd.yml', 'cd-api.yml']) {
      expect(read(`.github/workflows/${name}`), name).toMatch(
        /environment:\s*\n\s+name: staging\s*$/m,
      )
      expect(read(`.github/workflows/${name}`), name).not.toMatch(/name: develop\s*$/m)
    }
    const infraJob =
      read('.github/workflows/verify.yml')
        .split(/^ {2}infra:\s*$/m)[1]
        ?.split(/^ {2}[\w-]+:\s*$/m)[0] ?? ''
    expect(infraJob).toMatch(/^\s+environment: staging\s*$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Verify gate covers both Pulumi projects]]
  it('typechecks, tests and previews infra-repo alongside infra', () => {
    const verify = read('.github/workflows/verify.yml')
    expect(verify).toContain('npm ci --workspace infra --workspace infra-repo')
    expect(verify).toContain('npm run typecheck --workspace infra-repo')
    expect(verify).toContain('working-directory: infra-repo')
    expect(verify).toMatch(/pulumi stack select repo/)
  })

  // @lat: [[infra-tests#Infrastructure config#PWA image knows every workspace manifest]]
  it('copies the infra-repo manifest into the PWA image so npm ci resolves the lockfile', () => {
    expect(read('apps/pwa/Dockerfile')).toContain('COPY infra-repo/package.json infra-repo/')
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 01 no longer copies outputs into GitHub by hand]]
  it('drops the hand-copy of stack outputs from runbook 01 §5', () => {
    const section =
      read('docs/runbooks/01-initial-deployment.md')
        .split(/^## 5\. /m)[1]
        ?.split(/^## 6\. /m)[0] ?? ''
    expect(section).not.toContain('gh variable set')
    expect(section).toContain('ActionsEnvironmentVariable')
  })
})

describe('runbooks after the GitHub cut-over', () => {
  const runbook01 = () => read('docs/runbooks/01-initial-deployment.md')

  // @lat: [[infra-tests#Infrastructure config#No runbook sends the operator to the GitHub settings UI]]
  it('never tells the operator to set a variable or branch rule by hand', () => {
    for (const path of filesUnder('docs/runbooks')) {
      const text = read(path)
      expect(text, path).not.toContain('gh variable set')
      expect(text, path).not.toContain('Settings → Branches')
      expect(text, path).not.toMatch(
        /repository variables? (are|is) the operational source of truth/,
      )
    }
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 01 applies with the quota project override]]
  it('shows the quota-project form of pulumi up in runbook 01 §4 and runbook 03', () => {
    const step4 =
      runbook01()
        .split(/^## 4\. /m)[1]
        ?.split(/^## 5\. /m)[0] ?? ''
    expect(step4).toContain('USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT=')
    expect(read('docs/runbooks/03-infrastructure-change.md')).toContain(
      'USER_PROJECT_OVERRIDE=true',
    )
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 01 records the token expiry and the GitHub-side results]]
  it('records the token expiry in §8 and lists the environment and ruleset under what you have now', () => {
    const step8 =
      runbook01()
        .split(/^## 8\. /m)[1]
        ?.split(/^## What you have now/m)[0] ?? ''
    expect(step8).toMatch(/token.*expir/i)
    const summary = runbook01().split(/^## What you have now/m)[1] ?? ''
    expect(summary).toMatch(/environment/i)
    expect(summary).toMatch(/ruleset/i)
  })

  // @lat: [[infra-tests#Infrastructure config#README names both Pulumi projects and the environment as source of truth]]
  it('names infra-repo in the README and treats the GitHub environment as the source of truth', () => {
    const readme = read('docs/runbooks/README.md')
    expect(readme).toContain('infra-repo/')
    expect(readme).toMatch(/environment `staging`/)
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 05 explains the quota project error]]
  it('has a troubleshooting entry for the billing quota-project error', () => {
    expect(read('docs/runbooks/05-troubleshooting.md')).toMatch(/^## .*requires a quota project/m)
  })
})

describe('mobile release trust', () => {
  const program = () => read('infra/index.ts')
  const signingSecrets = [
    'asc-api-key',
    'asc-api-key-id',
    'asc-issuer-id',
    'ios-distribution-cert',
    'ios-cert-password',
    'ios-provisioning-profile',
    'android-upload-keystore',
    'android-keystore-password',
    'android-key-password',
  ]

  // @lat: [[infra-tests#Infrastructure config#Play identity is keyless]]
  it('declares a Play Developer API identity impersonated through the workload identity pool', () => {
    expect(program()).toContain("'androidpublisher.googleapis.com'")
    expect(program()).toMatch(/accountId: `\$\{serviceName\}-play-\$\{environment\}`/)
    const binding = program().split("'play-impersonation'")[1]?.split('})')[0] ?? ''
    expect(binding).toContain("role: 'roles/iam.workloadIdentityUser'")
    expect(binding).toContain('principalSet://iam.googleapis.com/')
    expect(program()).not.toMatch(/serviceaccount\.Key\(/)
  })

  // @lat: [[infra-tests#Infrastructure config#Signing material has a container and no version]]
  it('declares one empty Secret Manager container per piece of signing material', () => {
    const list = program().split('const signingSecrets')[1]?.split(']')[0] ?? ''
    for (const name of signingSecrets) {
      expect(list, name).toContain(`'${name}'`)
    }
    const after = program().split('const signingSecrets')[1] ?? ''
    expect(after).toMatch(/new gcp\.secretmanager\.Secret\(/)
    expect(after).not.toMatch(/new gcp\.secretmanager\.SecretVersion\(/)
  })

  // @lat: [[infra-tests#Infrastructure config#Deployer reads exactly the signing secrets]]
  it('grants the deployer secretAccessor per signing secret and never project-wide', () => {
    const after = program().split('const signingSecrets')[1] ?? ''
    const grant = after.split('SecretIamMember(')[1] ?? ''
    expect(grant).toContain("role: 'roles/secretmanager.secretAccessor'")
    expect(grant).toContain('deployAccount.email')
    for (const block of program().split('new gcp.projects.IAMMember(').slice(1)) {
      expect(block.split('})')[0]).not.toContain('secretmanager.secretAccessor')
    }
  })

  // @lat: [[infra-tests#Infrastructure config#Release identifiers reach the environment]]
  it('writes the Play identity and every secret id onto the GitHub environment', () => {
    const declared = program().split('const environmentVariables')[1]?.split('\n}')[0] ?? ''
    expect(declared).toMatch(/^\s+PLAY_SERVICE_ACCOUNT:/m)
    expect(program()).toMatch(/SECRET_\$\{name\.toUpperCase\(\)\.replace\(\/-\/g, '_'\)\}/)
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 07 has the two hand steps]]
  it('tells runbook 07 how to link the Play identity and add secret versions', () => {
    const runbook = read('docs/runbooks/07-mobile-release.md')
    expect(runbook).toContain('gcloud secrets versions add')
    expect(runbook).toMatch(/Users\s+and\s+permissions/)
    expect(runbook).not.toMatch(/putting the signing material in GitHub\s+secrets/)
  })
})

describe('mobile release workflow', () => {
  const workflow = () => read('.github/workflows/release-mobile.yml')

  // @lat: [[infra-tests#Infrastructure config#Release workflow runs on version tags in the environment]]
  it('runs on v* tags, one job per platform, in the staging environment', () => {
    expect(workflow()).toMatch(/^\s+tags:\s*(\[\s*['"]v\*['"]\s*\]|\n\s+- ['"]v\*['"])\s*$/m)
    const android =
      workflow()
        .split(/^ {2}android:\s*$/m)[1]
        ?.split(/^ {2}[\w-]+:\s*$/m)[0] ?? ''
    const ios =
      workflow()
        .split(/^ {2}ios:\s*$/m)[1]
        ?.split(/^ {2}[\w-]+:\s*$/m)[0] ?? ''
    expect(android).toContain('runs-on: ubuntu-latest')
    expect(ios).toContain('runs-on: macos-latest')
    for (const job of [android, ios]) {
      expect(job).toMatch(/^\s+environment: staging\s*$/m)
      expect(job).toContain('--build-number ${{ github.run_number }}')
      expect(job).toContain('--build-name')
    }
  })

  // @lat: [[infra-tests#Infrastructure config#Release workflow stores nothing in GitHub secrets]]
  it('references no GitHub secret except the workflow token', () => {
    const secrets = [...workflow().matchAll(/secrets\.([A-Za-z_]+)/g)].map((m) => m[1])
    expect(secrets.filter((s) => s !== 'GITHUB_TOKEN')).toEqual([])
  })

  // @lat: [[infra-tests#Infrastructure config#Release workflow reads signing material from Secret Manager]]
  it('fetches every piece of signing material with gcloud from the ids on the environment', () => {
    expect(workflow()).toContain('gcloud secrets versions access latest')
    for (const name of [
      'SECRET_ASC_API_KEY',
      'SECRET_ASC_API_KEY_ID',
      'SECRET_ASC_ISSUER_ID',
      'SECRET_IOS_DISTRIBUTION_CERT',
      'SECRET_IOS_CERT_PASSWORD',
      'SECRET_IOS_PROVISIONING_PROFILE',
      'SECRET_ANDROID_UPLOAD_KEYSTORE',
      'SECRET_ANDROID_KEYSTORE_PASSWORD',
      'SECRET_ANDROID_KEY_PASSWORD',
    ]) {
      expect(workflow(), name).toContain(`vars.${name}`)
    }
    expect(workflow()).toContain('vars.PLAY_SERVICE_ACCOUNT')
    expect(workflow()).toMatch(/uses: google-github-actions\/auth@v\d+/)
  })

  // @lat: [[infra-tests#Infrastructure config#Store uploads are scripted beside the app]]
  it('uploads with the committed Play script and the iOS Fastfile', () => {
    const play = read('apps/mobile/scripts/play-upload.sh')
    expect(play).toContain('androidpublisher.googleapis.com/androidpublisher/v3/applications/')
    expect(play).toContain('/tracks/internal')
    expect(play).toContain(':commit')
    const fastfile = read('apps/mobile/ios/fastlane/Fastfile')
    expect(fastfile).toContain('upload_to_testflight')
    expect(fastfile).toContain('app_store_connect_api_key')
    expect(fastfile).toContain('import_certificate')
    expect(workflow()).toContain('scripts/play-upload.sh')
    expect(workflow()).toContain('fastlane')
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 07 describes the tag-driven release]]
  it('turns runbook 07 into the release procedure', () => {
    const runbook = read('docs/runbooks/07-mobile-release.md')
    expect(runbook).toContain('release-mobile.yml')
    expect(runbook).toMatch(/git tag v/)
    expect(runbook).not.toMatch(/does not\s+yet build a release/)
    expect(runbook).toMatch(/processing/i)
  })

  // @lat: [[infra-tests#Infrastructure config#Info.plist answers export compliance]]
  it('declares ITSAppUsesNonExemptEncryption false in Info.plist and says so in runbook 07', () => {
    const plist = read('apps/mobile/ios/Runner/Info.plist')
    expect(plist).toMatch(/<key>ITSAppUsesNonExemptEncryption<\/key>\s*<false\/>/)
    const runbook = read('docs/runbooks/07-mobile-release.md')
    expect(runbook).toContain('ITSAppUsesNonExemptEncryption')
  })
})

describe('runbook 01 keeps the two Pulumi projects apart', () => {
  const runbook01 = () => read('docs/runbooks/01-initial-deployment.md')
  const step = (n: number) =>
    runbook01()
      .split(new RegExp(`^## ${n}\\. `, 'm'))[1]
      ?.split(/^## /m)[0] ?? ''

  // @lat: [[infra-tests#Infrastructure config#Runbook 01 gives the repository project its own step]]
  it('keeps infra-repo out of step 3 and gives it a step of its own', () => {
    expect(step(3)).not.toContain('infra-repo')
    expect(runbook01()).toMatch(/^## \d+\. .*repository project/im)
    const repoStep =
      runbook01()
        .split(/^## \d+\. .*repository project.*$/im)[1]
        ?.split(/^## /m)[0] ?? ''
    expect(repoStep).toMatch(/^\$ cd .*infra-repo\s*$/m)
    expect(repoStep).toMatch(/^\$ pulumi stack select repo\s*$/m)
    expect(repoStep).toContain('pulumi import github:index/repositoryRuleset:RepositoryRuleset')
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 01 import ids carry the repository prefix]]
  it('prefixes every import id with the repository name, not the owner', () => {
    const imports = runbook01().match(/pulumi import \S+ \\?\n?\s*\S+ \S+/g) ?? []
    expect(imports.length).toBeGreaterThanOrEqual(2)
    for (const line of imports) {
      expect(line).toMatch(/ reward-app:\S+$/)
      expect(line).not.toContain('helpmebrands/')
    }
  })
})

describe('signing material procedure and token record', () => {
  const runbook07 = () => read('docs/runbooks/07-mobile-release.md')

  // @lat: [[infra-tests#Infrastructure config#Runbook 07 walks through every piece of signing material]]
  it('has a subsection for the keystore, the API key, the certificate and the profile', () => {
    const signing =
      runbook07()
        .split(/^## Signing material/m)[1]
        ?.split(/^## /m)[0] ?? ''
    for (const heading of [
      'upload keystore',
      'App Store Connect API key',
      'distribution certificate',
      'provisioning profile',
    ]) {
      expect(signing, heading).toMatch(new RegExp(`^### .*${heading}`, 'im'))
    }
    expect(signing).toContain('gcloud secrets versions add')
    expect(signing).toMatch(/^\$ export STACK=staging$/m)
    expect(signing).toMatch(/Play App Signing/)
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 07 says store records are per app id]]
  it('states that store records are per app id, not per environment', () => {
    expect(runbook07()).toMatch(/one record\s+per app/i)
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 07 verifies the profile before storing it]]
  it('checks the profile is for the app id before adding the secret version', () => {
    const runbook = runbook07()
    const profile =
      runbook.split(/^### iOS: the provisioning profile/m)[1]?.split(/^### /m)[0] ?? ''
    expect(runbook).toContain('XC com helpmebrands reward')
    expect(profile).toContain('/v1/profiles')
    expect(profile).toContain('security cms -D')
    expect(profile.indexOf('application-identifier')).toBeGreaterThan(-1)
    expect(profile.indexOf('application-identifier')).toBeLessThan(
      profile.indexOf('gcloud secrets versions add'),
    )
  })

  // @lat: [[infra-tests#Infrastructure config#Runbook 07 reads binaries back with --out-file]]
  it('reads the binaries back with --out-file and proves them in the check step', () => {
    const signing =
      runbook07()
        .split(/^## Signing material/m)[1]
        ?.split(/^## /m)[0] ?? ''
    const check = signing.split(/^### Check and clean up/m)[1] ?? ''
    expect(check).toMatch(/--out-file check\.p12/)
    expect(check).toMatch(/security import check\.p12/)
    expect(check).toMatch(/security cms -D -i check\.mobileprovision/)
    expect(check).toMatch(/stdout/)
    expect(signing).not.toMatch(/'X{10}' \| gcloud/)
    expect(signing).toMatch(/read -r ASC_KEY_ID/)
  })

  // @lat: [[infra-tests#Infrastructure config#README records the iOS signing expiry]]
  it('records the iOS certificate expiry in the README table', () => {
    expect(read('docs/runbooks/README.md')).toMatch(/^\| iOS signing \|.*2027-09-21.*\|$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#README records the GitHub token]]
  it('records who minted the GitHub token and its expiry in the README table', () => {
    const readme = read('docs/runbooks/README.md')
    expect(readme).toMatch(/^\| GitHub token \|.*oravecz.*\|$/m)
    expect(readme).toMatch(/^\| GitHub token \|.*no expiry.*\|$/m)
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

describe('mobile Makefile', () => {
  // @lat: [[infra-tests#Infrastructure config#Mobile Makefile is the app's script runner]]
  it('defines the documented targets through fvm and the README lists them', () => {
    const makefile = read('apps/mobile/Makefile')
    for (const target of ['help', 'init', 'build', 'test', 'e2e', 'deploy']) {
      expect(makefile, target).toMatch(new RegExp(`^${target}:.*## `, 'm'))
    }
    expect(makefile).toMatch(/^FLUTTER\s*:?=\s*fvm flutter$/m)
    expect(makefile).not.toMatch(/^\t+(flutter|dart) /m)
    const readme = read('apps/mobile/README.md')
    for (const target of [
      'make init',
      'make build',
      'make test',
      'make e2e',
      'make deploy',
      'make help',
    ]) {
      expect(readme).toContain(target)
    }
  })

  // @lat: [[infra-tests#Infrastructure config#macOS is a local run target only]]
  it('accepts macos for build and run, with the network entitlement, but never for deploy', () => {
    const makefile = read('apps/mobile/Makefile')
    expect(makefile).toMatch(/^PLATFORMS\s*:?=.*\bmacos\b/m)
    expect(makefile).toMatch(/^build-macos:\n\t\$\(FLUTTER\) build macos/m)
    expect(makefile).toMatch(/^build:[\s\S]*?\$\(or \$\(PLATFORM\),\$\(RELEASE_PLATFORMS\)\)/m)
    expect(makefile).toMatch(/^RELEASE_PLATFORMS\s*:?=\s*ios android$/m)
    expect(read('apps/mobile/scripts/pick-device.sh')).toMatch(/^\s*macos\)/m)
    for (const profile of ['DebugProfile', 'Release']) {
      const entitlements = read(`apps/mobile/macos/Runner/${profile}.entitlements`)
      expect(entitlements, profile).toContain('com.apple.security.network.client')
    }
    expect(existsSync(join(root, 'apps/mobile/macos/Podfile'))).toBe(false)
    const readme = read('apps/mobile/README.md')
    expect(readme).toContain('make run macos')
    expect(readme).toContain('make build macos')
    const release = read('.github/workflows/release-mobile.yml')
    expect(release).not.toMatch(/build macos/)
    expect(read('lat.md/mobile/mobile-architecture.md')).toMatch(/## Make targets[\s\S]*macos/)
  })
})

describe('local verify', () => {
  // @lat: [[infra-tests#Infrastructure config#Root Makefile runs the verify gate locally]]
  it('has a root Makefile with verify targets and a pre-push hook that calls it', () => {
    const makefile = read('Makefile')
    for (const target of ['help', 'init', 'verify', 'verify-full']) {
      expect(makefile, target).toMatch(new RegExp(`^${target}:.*## `, 'm'))
    }
    expect(makefile).toMatch(/core\.hooksPath \.githooks/)
    const hook = read('.githooks/pre-push')
    expect(hook).toMatch(/make verify/)
    expect(statSync(join(root, '.githooks/pre-push')).mode & 0o111).not.toBe(0)
    expect(read('docs/runbooks/02-routine-change.md')).toContain('make verify')
  })
})

describe('sign-in', () => {
  const program = () => read('infra/index.ts')

  // @lat: [[infra-tests#Infrastructure config#Identity Platform signs people in with Google and Apple]]
  it('turns on Firebase and Identity Platform with the Google and Apple providers', () => {
    const p = program()
    expect(p).toContain("'identitytoolkit.googleapis.com'")
    expect(p).toContain("'firebase.googleapis.com'")
    expect(p).toMatch(/new gcp\.firebase\.Project\(/)
    expect(p).toMatch(/new gcp\.identityplatform\.Config\(/)
    expect(p).toMatch(/idpId: 'google\.com'/)
    expect(p).toMatch(/idpId: 'apple\.com'/)
    expect(p).toMatch(/config\.getSecret\('googleOAuthClientSecret'\)/)
    for (const key of ['googleOAuthClientId', 'appleServicesId']) {
      expect(p, key).toMatch(new RegExp(`config\\.get\\('${key}'\\)`))
    }
  })

  // @lat: [[infra-tests#Infrastructure config#The app is registered with Firebase on both platforms]]
  it('registers the iOS and Android apps and exports their options', () => {
    const p = program()
    expect(p).toMatch(/new gcp\.firebase\.AppleApp\(/)
    expect(p).toMatch(/new gcp\.firebase\.AndroidApp\(/)
    expect(p).toMatch(/const appId = 'com\.helpmebrands\.reward'/)
    for (const output of [
      'firebaseIosAppId',
      'firebaseAndroidAppId',
      'firebaseIosApiKey',
      'firebaseAndroidApiKey',
      'firebaseIosUrlScheme',
    ]) {
      expect(p, output).toMatch(new RegExp(`^export const ${output} = `, 'm'))
    }
  })

  // @lat: [[infra-tests#Infrastructure config#The sign-in credentials are the runbook's keys]]
  it('declares the runbook 08 keys and commits the Apple team id', () => {
    const project = read('infra/Pulumi.yaml')
    for (const key of [
      'googleOAuthClientId',
      'googleOAuthClientSecret',
      'appleServicesId',
      'appleKeyId',
      'appleServicesKey',
      'appleTeamId',
    ]) {
      expect(project, key).toMatch(new RegExp(`^  ${key}:$`, 'm'))
      expect(read('docs/runbooks/08-sign-in-providers.md'), key).toContain(`reward-app:${key}`)
    }
    expect(read('infra/Pulumi.staging.yaml')).toMatch(/^ {2}reward-app:appleTeamId: LMFUSVPCDH$/m)
  })

  // @lat: [[infra-tests#Infrastructure config#The api knows its Firebase project]]
  it('tells the api which Firebase project its tokens come from', () => {
    const api = program().split("new gcp.cloudrunv2.Service(\n  'api',")[1]?.split('\n)\n')[0] ?? ''
    expect(api).toMatch(/name: 'FIREBASE_PROJECT_ID'/)
  })
})

describe('api contract', () => {
  // @lat: [[infra-tests#Infrastructure config#The api spec is linted as OpenAPI in CI and locally]]
  it('lints services/api/openapi.yaml with a pinned Redocly CLI in the api job and make api', () => {
    const lint = /npx --yes @redocly\/cli@\d+\.\d+\.\d+ lint services\/api\/openapi\.yaml/
    const api =
      read('.github/workflows/verify.yml')
        .split(/^ {2}api:$/m)[1]
        ?.split(/^ {2}\w+:$/m)[0] ?? ''
    expect(api, 'the api job').toMatch(lint)
    const target = read('Makefile').split(/^api:/m)[1]?.split(/^\w+:/m)[0] ?? ''
    expect(target, 'make api').toMatch(lint)
    expect(existsSync(join(root, 'services/api/openapi.yaml'))).toBe(true)
  })
})

describe('workflow action runtimes', () => {
  // The Node 24 floor for every action the workflows use. An action's own
  // action.yml declares `runs.using`; a major below the floor still declares
  // node20 and makes the runner print the Node 20 deprecation warning on every
  // run. Verified on 2026-09-22 with
  //   gh api repos/<owner>/<repo>/contents/action.yml?ref=<tag>
  // subosito/flutter-action is composite and nests actions/cache@v5 (node24).
  const node24Floor: Record<string, number> = {
    'actions/checkout': 5,
    'actions/setup-node': 6,
    'actions/upload-artifact': 6,
    'actions/download-artifact': 8,
    'docker/build-push-action': 7,
    'docker/setup-buildx-action': 4,
    'google-github-actions/auth': 3,
    'google-github-actions/setup-gcloud': 3,
    'google-github-actions/deploy-cloudrun': 3,
    'pulumi/actions': 7,
    'subosito/flutter-action': 2,
  }

  const workflows = filesUnder('.github/workflows').filter((path) => path.endsWith('.yml'))

  const usesIn = (path: string) =>
    [...read(path).matchAll(/^\s*(?:- )?uses:\s*([^\s@]+)@(\S+)/gm)].map(([, action, ref]) => ({
      action: action ?? '',
      ref: ref ?? '',
    }))

  // @lat: [[infra-tests#Infrastructure config#Every workflow action declares the Node 24 runtime]]
  it('pins every third-party action at a major whose action.yml declares node24', () => {
    for (const path of workflows) {
      for (const { action, ref } of usesIn(path)) {
        if (action.startsWith('./')) continue
        const floor = node24Floor[action] ?? Number.POSITIVE_INFINITY
        expect(floor, `${path} uses ${action}, which is not in the audited table`).toBeLessThan(
          Number.POSITIVE_INFINITY,
        )
        const major = Number(/^v(\d+)/.exec(ref)?.[1])
        expect(
          major,
          `${path} pins ${action}@${ref}; the Node 24 floor is v${floor}`,
        ).toBeGreaterThanOrEqual(floor)
      }
    }
  })

  // @lat: [[infra-tests#Infrastructure config#Pulumi CLI comes from the maintained action]]
  it('installs the Pulumi CLI with pulumi/actions in install-only mode, not setup-pulumi', () => {
    const verify = read('.github/workflows/verify.yml')
    expect(verify).not.toMatch(/uses: pulumi\/setup-pulumi/)
    const pulumiWith = /uses: pulumi\/actions@v\d+\n\s+with:\n((?:[ \t]+\S.*\n)+)/.exec(verify)?.[1]
    expect(pulumiWith, 'pulumi/actions step with a `with:` block').toBeDefined()
    expect(pulumiWith).toMatch(/^\s+pulumi-version: /m)
    expect(pulumiWith).not.toMatch(/^\s+command:/m)
  })

  // @lat: [[infra-tests#Infrastructure config#Nobody opts back into Node 20]]
  it('never sets ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION anywhere in the repository', () => {
    const tracked = ['.github', 'docs', 'infra', 'infra-repo', 'Makefile'].flatMap((entry) =>
      statSync(join(root, entry)).isDirectory() ? filesUnder(entry) : [entry],
    )
    for (const path of tracked) {
      expect(read(path), path).not.toContain('ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION')
    }
  })

  // @lat: [[infra-tests#Infrastructure config#Dependabot watches the workflow actions]]
  it('has Dependabot watching the github-actions ecosystem', () => {
    expect(existsSync(join(root, '.github/dependabot.yml'))).toBe(true)
    const dependabot = read('.github/dependabot.yml')
    expect(dependabot).toMatch(/^version: 2$/m)
    expect(dependabot).toMatch(/package-ecosystem: ["']?github-actions["']?/)
  })
})
