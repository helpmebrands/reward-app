/**
 * HelpMe Reward infrastructure.
 *
 * Everything the app needs to be built by GitHub and served by Cloud Run:
 * an image registry, the service itself, and a keyless trust path from this
 * repository into the project.
 *
 * The division of ownership is the thing to understand before changing
 * anything here. **Pulumi owns the shape of the service; CI owns which image is
 * running.** Every deploy points Cloud Run at a new digest, and if Pulumi also
 * managed the image it would revert to whatever the last `pulumi up` saw — so
 * the image field is explicitly ignored (see `ignoreChanges` below). Without
 * that, an infrastructure change quietly rolls production back.
 */

import * as gcp from '@pulumi/gcp'
import * as pulumi from '@pulumi/pulumi'
import * as random from '@pulumi/random'

const config = new pulumi.Config('reward-app')
const gcpConfig = new pulumi.Config('gcp')

const project = gcpConfig.require('project')
const region = gcpConfig.get('region') ?? 'us-central1'
const serviceName = config.get('serviceName') ?? 'reward-app'
const minInstances = config.getNumber('minInstances') ?? 0
const maxInstances = config.getNumber('maxInstances') ?? 4
const customDomain = config.get('customDomain') ?? ''
const apiServiceName = config.get('apiServiceName') ?? 'reward-api'
const dbTier = config.get('dbTier') ?? 'db-f1-micro'
/** Bootstrapped by hand before the stack exists (runbook 01); the deployer is
 * granted read and lock access to them so CI can preview. */
const stateBucket = config.require('stateBucket')
const secretsKey = config.require('secretsKey')
/** Secret config: the id is not sensitive in itself, but the repository is
 * public and a billing account id is a foothold for social engineering. */
const billingAccount = config.requireSecret('billingAccount')
const budgetAmount = config.getNumber('budgetAmount') ?? 25

/**
 * The repository permitted to deploy, as `owner/name`.
 *
 * This is a security control, not a label. It becomes the attribute condition
 * on the identity provider below: without it, a workflow in *any* GitHub
 * repository could mint a token for this project.
 */
const githubRepo = config.require('githubRepo')
if (!/^[\w.-]+\/[\w.-]+$/.test(githubRepo)) {
  throw new Error(`reward-app:githubRepo must look like "owner/name", got "${githubRepo}"`)
}

/** The stack name doubles as the environment: `dev`, `prod`, … */
const environment = pulumi.getStack()
const tags = { app: 'reward-app', environment, 'managed-by': 'pulumi' }

// ---------------------------------------------------------------------------
// APIs
// ---------------------------------------------------------------------------

/**
 * Enabling a service is slow and eventually consistent, so everything that uses
 * one depends on it explicitly rather than relying on ordering luck — a fresh
 * project otherwise fails the first `up` with a confusing permission error.
 *
 * `disableOnDestroy: false` so tearing down this stack does not switch APIs off
 * underneath anything else living in the project.
 */
const services = [
  'artifactregistry.googleapis.com',
  'run.googleapis.com',
  'iam.googleapis.com',
  'iamcredentials.googleapis.com',
  'sts.googleapis.com',
  'cloudresourcemanager.googleapis.com',
  'sqladmin.googleapis.com',
  'secretmanager.googleapis.com',
  'cloudkms.googleapis.com',
  'billingbudgets.googleapis.com',
].map(
  (service) =>
    new gcp.projects.Service(`api-${service.split('.')[0]}`, {
      project,
      service,
      disableOnDestroy: false,
    }),
)

const dependsOnApis = { dependsOn: services }

// ---------------------------------------------------------------------------
// Image registry
// ---------------------------------------------------------------------------

const repository = new gcp.artifactregistry.Repository(
  'images',
  {
    project,
    location: region,
    repositoryId: `${serviceName}-${environment}`,
    format: 'DOCKER',
    description: `Container images for HelpMe Reward (${environment})`,
    labels: tags,
    // Every commit to develop pushes an image, so without a policy this grows
    // without bound and bills forever. Keeping recent images is what makes a
    // rollback possible, so the retention window is deliberately generous.
    cleanupPolicies: [
      {
        id: 'keep-recent-releases',
        action: 'KEEP',
        mostRecentVersions: { keepCount: 30 },
      },
      {
        id: 'drop-stale-untagged',
        action: 'DELETE',
        condition: {
          tagState: 'UNTAGGED',
          olderThan: '604800s', // 7 days
        },
      },
    ],
  },
  dependsOnApis,
)

// ---------------------------------------------------------------------------
// Runtime identity
// ---------------------------------------------------------------------------

/**
 * The identity the container runs as.
 *
 * It is granted nothing. HelpMe Reward serves static files and holds all user
 * data in the browser, so the container has no reason to reach any Google API —
 * and running as the default compute service account (which is broadly
 * privileged) would hand an attacker who achieved RCE a project-wide identity
 * for no benefit.
 */
const runtimeAccount = new gcp.serviceaccount.Account(
  'runtime',
  {
    project,
    accountId: `${serviceName}-run-${environment}`.slice(0, 30),
    displayName: `HelpMe Reward runtime (${environment})`,
    description: 'Runs the HelpMe Reward container. Intentionally holds no roles.',
  },
  dependsOnApis,
)

// ---------------------------------------------------------------------------
// The service
// ---------------------------------------------------------------------------

/**
 * What CI writes on a Cloud Run service at each deploy: the image, the
 * deploy labels and the revision name. Pulumi must not touch any of them.
 * Apply template changes with `pulumi up --refresh`, so the image input in
 * state is the live digest and not the bootstrap image below.
 */
const ciOwnedServiceFields = [
  'template.containers[0].image',
  'template.labels',
  'template.revision',
  'labels["managed-by"]',
  'labels["commit-sha"]',
  'client',
  'clientVersion',
  'scaling',
]

/**
 * A public image that serves a placeholder page, used only for the first
 * `pulumi up`. Cloud Run cannot create a service without an image, but the real
 * one does not exist until CI has built it. The first deploy replaces this
 * within minutes, and `ignoreChanges` below keeps Pulumi from putting it back.
 */
const BOOTSTRAP_IMAGE = 'us-docker.pkg.dev/cloudrun/container/hello'

const service = new gcp.cloudrunv2.Service(
  'app',
  {
    project,
    location: region,
    name: serviceName,
    description: `HelpMe Reward (${environment})`,
    labels: tags,
    ingress: 'INGRESS_TRAFFIC_ALL',
    // The app is a public website, so anyone may invoke it. This is the one
    // genuinely public setting in the stack and is worth seeing explicitly.
    // It is a service setting rather than an `allUsers` invoker binding
    // because the organisation enforces domain-restricted sharing, which
    // rejects `allUsers` in any IAM policy; skipping the invoker check for
    // this one service is narrower than carving a policy exception for the
    // whole project.
    invokerIamDisabled: true,
    // Guards against `pulumi destroy` taking production with it. Flip to false
    // deliberately when you actually mean to remove the service.
    deletionProtection: environment === 'prod',
    template: {
      serviceAccount: runtimeAccount.email,
      // Serving static files is cheap; the ceiling exists to bound spend if the
      // service is ever crawled hard.
      scaling: { minInstanceCount: minInstances, maxInstanceCount: maxInstances },
      // nginx handles many connections per instance happily, so a high
      // concurrency keeps the instance count (and the bill) near zero.
      maxInstanceRequestConcurrency: 80,
      timeout: '30s',
      containers: [
        {
          image: BOOTSTRAP_IMAGE,
          // Cloud Run injects PORT to match; the nginx template reads it.
          ports: { name: 'http1', containerPort: 8080 },
          resources: {
            limits: { cpu: '1', memory: '512Mi' },
            // Billing only while a request is in flight, which for a static
            // site is almost never.
            cpuIdle: true,
            startupCpuBoost: true,
          },
          startupProbe: {
            // The container is nginx serving files from its own filesystem, so
            // it is ready almost immediately; failing fast surfaces a broken
            // image as a failed deploy rather than a hung one.
            tcpSocket: { port: 8080 },
            initialDelaySeconds: 0,
            periodSeconds: 3,
            failureThreshold: 10,
            timeoutSeconds: 3,
          },
        },
      ],
    },
  },
  {
    ...dependsOnApis,
    // CI owns the image. See the note at the top of this file — without this,
    // `pulumi up` would roll the service back to whichever digest the last
    // `up` recorded, turning an unrelated infrastructure change into a silent
    // deployment of old code.
    // The API also reports back a service-level `scaling` block this program
    // never sets (instance scaling lives in the template); without ignoring
    // it, every preview proposes removing it. The deploy action also stamps
    // `managed-by` and `commit-sha` labels and names the revision; those are
    // CI's too, or every refreshed `up` rolls a new revision to strip them.
    ignoreChanges: ciOwnedServiceFields,
  },
)

// ---------------------------------------------------------------------------
// The database
// ---------------------------------------------------------------------------

/**
 * One PostgreSQL 16 instance for the api, at the smallest tier by default.
 *
 * Public IP with no authorised networks: nothing connects directly. Cloud Run
 * reaches it through the Cloud SQL connector (a unix socket the platform
 * mounts), which authenticates as the runtime identity and encrypts on the
 * wire, so `ENCRYPTED_ONLY` costs nothing and refuses any plaintext client.
 * Backups are on because the retention is small and a database without them
 * is a footgun waiting for prod.
 */
const dbInstance = new gcp.sql.DatabaseInstance(
  'db',
  {
    project,
    region,
    name: `${apiServiceName}-db-${environment}`,
    databaseVersion: 'POSTGRES_16',
    deletionProtection: environment === 'prod',
    settings: {
      tier: dbTier,
      edition: 'ENTERPRISE',
      availabilityType: 'ZONAL',
      diskSize: 10,
      diskAutoresize: true,
      deletionProtectionEnabled: environment === 'prod',
      ipConfiguration: { ipv4Enabled: true, sslMode: 'ENCRYPTED_ONLY' },
      backupConfiguration: { enabled: true, startTime: '03:00' },
      userLabels: tags,
    },
  },
  dependsOnApis,
)

const database = new gcp.sql.Database('db-reward', {
  project,
  instance: dbInstance.name,
  name: 'reward',
})

/**
 * The api's database user. Its password is generated here and never seen by
 * a human: it lives encrypted in the stack state (which is why the stack had
 * to move to the KMS secrets provider first) and in Secret Manager below.
 * Alphanumeric only so it can sit inside a URL unencoded.
 */
const dbPassword = new random.RandomPassword('db-password', { length: 32, special: false })

const dbUser = new gcp.sql.User('db-api', {
  project,
  instance: dbInstance.name,
  name: 'api',
  password: dbPassword.result,
})

/**
 * The whole connection URL as one secret, so the api reads a single
 * `DATABASE_URL` whether it runs locally against docker compose or on Cloud
 * Run. The empty authority plus `host=/cloudsql/…` is the libpq form for a
 * unix socket; the Dart driver connects to that path verbatim rather than
 * appending the socket file name as libpq does, so the URL names the file.
 * `sslmode=disable` because the connector already encrypts and the socket
 * has no TLS to offer.
 */
const databaseUrlSecret = new gcp.secretmanager.Secret(
  'database-url',
  {
    project,
    secretId: `${apiServiceName}-database-url-${environment}`,
    labels: tags,
    replication: { auto: {} },
  },
  dependsOnApis,
)

new gcp.secretmanager.SecretVersion('database-url-version', {
  secret: databaseUrlSecret.id,
  secretData: pulumi.secret(
    pulumi.interpolate`postgres://${dbUser.name}:${dbPassword.result}@/${database.name}?host=/cloudsql/${dbInstance.connectionName}/.s.PGSQL.5432&sslmode=disable`,
  ),
})

/**
 * The identity the api container runs as. Unlike the PWA's runtime account it
 * needs exactly two things: to open the Cloud SQL connector (`cloudsql.client`
 * is only grantable project-wide) and to read the one secret above.
 */
const apiRuntimeAccount = new gcp.serviceaccount.Account(
  'api-runtime',
  {
    project,
    accountId: `${apiServiceName}-run-${environment}`.slice(0, 30),
    displayName: `HelpMe Reward api runtime (${environment})`,
    description: 'Runs the api container. Cloud SQL client and reader of its own database secret.',
  },
  dependsOnApis,
)

new gcp.projects.IAMMember('api-runtime-cloudsql-client', {
  project,
  role: 'roles/cloudsql.client',
  member: pulumi.interpolate`serviceAccount:${apiRuntimeAccount.email}`,
})

const apiRuntimeReadsDatabaseUrl = new gcp.secretmanager.SecretIamMember(
  'api-runtime-reads-database-url',
  {
    project,
    secretId: databaseUrlSecret.secretId,
    role: 'roles/secretmanager.secretAccessor',
    member: pulumi.interpolate`serviceAccount:${apiRuntimeAccount.email}`,
  },
)

// ---------------------------------------------------------------------------
// The api service and its migration job
// ---------------------------------------------------------------------------

/** Shared by the service and the job: the database socket and the URL. */
const cloudSqlVolume = {
  name: 'cloudsql',
  cloudSqlInstance: { instances: [dbInstance.connectionName] },
}
const cloudSqlMount = { name: 'cloudsql', mountPath: '/cloudsql' }
const databaseUrlEnv = {
  name: 'DATABASE_URL',
  valueSource: {
    secretKeyRef: { secret: databaseUrlSecret.secretId, version: 'latest' },
  },
}

/**
 * The api. Same ownership rule as the PWA service: Pulumi owns the shape, CI
 * owns the image, so the image is ignored after the bootstrap. Public like
 * the PWA (there are no accounts; a device registers its own token), running
 * as the api identity with the Cloud SQL connector mounted and the whole
 * connection URL injected from Secret Manager. Depends on the secret binding
 * because Cloud Run checks at revision creation that the identity can read
 * every secret it references.
 */
const apiService = new gcp.cloudrunv2.Service(
  'api',
  {
    project,
    location: region,
    name: apiServiceName,
    description: `HelpMe Reward api (${environment})`,
    labels: tags,
    ingress: 'INGRESS_TRAFFIC_ALL',
    invokerIamDisabled: true,
    deletionProtection: environment === 'prod',
    template: {
      serviceAccount: apiRuntimeAccount.email,
      // Gen2, explicitly: on the first-generation sandbox a Dart connect to
      // the Cloud SQL unix socket never completes, and the request dies at
      // the timeout with nothing in the log. The job below gets gen2 by
      // default; the service does not.
      executionEnvironment: 'EXECUTION_ENVIRONMENT_GEN2',
      scaling: { minInstanceCount: minInstances, maxInstanceCount: maxInstances },
      maxInstanceRequestConcurrency: 80,
      timeout: '30s',
      volumes: [cloudSqlVolume],
      containers: [
        {
          image: BOOTSTRAP_IMAGE,
          ports: { name: 'http1', containerPort: 8080 },
          resources: {
            limits: { cpu: '1', memory: '512Mi' },
            cpuIdle: true,
            startupCpuBoost: true,
          },
          envs: [databaseUrlEnv],
          volumeMounts: [cloudSqlMount],
          startupProbe: {
            tcpSocket: { port: 8080 },
            initialDelaySeconds: 0,
            periodSeconds: 3,
            failureThreshold: 10,
            timeoutSeconds: 3,
          },
        },
      ],
    },
  },
  {
    dependsOn: [...services, apiRuntimeReadsDatabaseUrl],
    ignoreChanges: ciOwnedServiceFields,
  },
)

/**
 * The migration job: the same image as the service with `/migrate` as its
 * command, run once by CD before each deploy (`cd-api.yml`), so a broken
 * migration fails the deploy rather than every replica at startup. No
 * retries: a migration that failed once should be read, not rerun blindly.
 * CI owns its image too.
 */
const migrateJob = new gcp.cloudrunv2.Job(
  'api-migrate',
  {
    project,
    location: region,
    name: `${apiServiceName}-migrate`,
    labels: tags,
    deletionProtection: environment === 'prod',
    template: {
      template: {
        serviceAccount: apiRuntimeAccount.email,
        executionEnvironment: 'EXECUTION_ENVIRONMENT_GEN2',
        maxRetries: 0,
        timeout: '600s',
        volumes: [cloudSqlVolume],
        containers: [
          {
            image: BOOTSTRAP_IMAGE,
            commands: ['/migrate'],
            resources: { limits: { cpu: '1', memory: '512Mi' } },
            envs: [databaseUrlEnv],
            volumeMounts: [cloudSqlMount],
          },
        ],
      },
    },
  },
  {
    dependsOn: [...services, apiRuntimeReadsDatabaseUrl],
    ignoreChanges: ['template.template.containers[0].image', 'client', 'clientVersion'],
  },
)

// ---------------------------------------------------------------------------
// Keyless deploys from GitHub
// ---------------------------------------------------------------------------

/**
 * Workload Identity Federation.
 *
 * GitHub Actions presents a short-lived OIDC token; Google exchanges it for
 * credentials. No service-account key is ever created, so there is no
 * long-lived secret in the repository to leak, rotate, or find in a log.
 */
const pool = new gcp.iam.WorkloadIdentityPool(
  'github-pool',
  {
    project,
    workloadIdentityPoolId: `github-${environment}`,
    displayName: `GitHub Actions (${environment})`,
    description: 'Trust anchor for keyless deploys from GitHub.',
  },
  dependsOnApis,
)

const provider = new gcp.iam.WorkloadIdentityPoolProvider(
  'github-provider',
  {
    project,
    workloadIdentityPoolId: pool.workloadIdentityPoolId,
    workloadIdentityPoolProviderId: 'github',
    displayName: 'GitHub OIDC',
    attributeMapping: {
      'google.subject': 'assertion.sub',
      'attribute.repository': 'assertion.repository',
      'attribute.repository_owner': 'assertion.repository_owner',
      'attribute.ref': 'assertion.ref',
    },
    // The control that makes the pool safe. Without a condition, any GitHub
    // workflow anywhere can present a token this provider will accept; the
    // binding below narrows it to one repository, and this narrows the
    // provider itself to the same owner as defence in depth.
    attributeCondition: pulumi.interpolate`assertion.repository_owner == "${githubRepo.split('/')[0]}"`,
    oidc: { issuerUri: 'https://token.actions.githubusercontent.com' },
  },
  dependsOnApis,
)

/** The identity GitHub assumes. Its roles are the entire blast radius of a
 * compromised workflow, so they are scoped to exactly two resources. */
const deployAccount = new gcp.serviceaccount.Account(
  'deployer',
  {
    project,
    accountId: `${serviceName}-deploy-${environment}`.slice(0, 30),
    displayName: `HelpMe Reward deployer (${environment})`,
    description: 'Assumed by GitHub Actions to push images and deploy revisions.',
  },
  dependsOnApis,
)

/**
 * Only workflows running in this repository may impersonate the deployer.
 *
 * `attribute.repository` rather than `google.subject`, so the trust survives
 * branch renames and does not need a binding per workflow. Narrow this further
 * to `attribute.ref == "refs/heads/develop"` if deploys should be impossible
 * from any other branch.
 */
new gcp.serviceaccount.IAMMember('deployer-impersonation', {
  serviceAccountId: deployAccount.name,
  role: 'roles/iam.workloadIdentityUser',
  member: pulumi.interpolate`principalSet://iam.googleapis.com/${pool.name}/attribute.repository/${githubRepo}`,
})

/** Push images — writer, not admin: CI never needs to delete a release. */
new gcp.artifactregistry.RepositoryIamMember('deployer-can-push', {
  project,
  location: repository.location,
  repository: repository.name,
  role: 'roles/artifactregistry.writer',
  member: pulumi.interpolate`serviceAccount:${deployAccount.email}`,
})

/**
 * Deploy revisions of this one service. `run.developer` scoped to the service
 * rather than `run.admin` on the project, so a compromised workflow cannot
 * create new services or touch anything else in Cloud Run.
 */
new gcp.cloudrunv2.ServiceIamMember('deployer-can-deploy', {
  project,
  location: service.location,
  name: service.name,
  role: 'roles/run.developer',
  member: pulumi.interpolate`serviceAccount:${deployAccount.email}`,
})

/**
 * Deploying a service that runs *as* another identity requires permission to
 * act as it. Easy to miss, and it fails at deploy time with a message that
 * does not obviously say so.
 */
new gcp.serviceaccount.IAMMember('deployer-can-act-as-runtime', {
  serviceAccountId: runtimeAccount.name,
  role: 'roles/iam.serviceAccountUser',
  member: pulumi.interpolate`serviceAccount:${deployAccount.email}`,
})

/** The same three grants for the api: deploy its service, run its job, act
 * as its identity. Still `run.developer` per resource, never project-wide. */
new gcp.cloudrunv2.ServiceIamMember('deployer-can-deploy-api', {
  project,
  location: apiService.location,
  name: apiService.name,
  role: 'roles/run.developer',
  member: pulumi.interpolate`serviceAccount:${deployAccount.email}`,
})

new gcp.cloudrunv2.JobIamMember('deployer-can-run-migrations', {
  project,
  location: migrateJob.location,
  name: migrateJob.name,
  role: 'roles/run.developer',
  member: pulumi.interpolate`serviceAccount:${deployAccount.email}`,
})

new gcp.serviceaccount.IAMMember('deployer-can-act-as-api-runtime', {
  serviceAccountId: apiRuntimeAccount.name,
  role: 'roles/iam.serviceAccountUser',
  member: pulumi.interpolate`serviceAccount:${deployAccount.email}`,
})

/**
 * `pulumi preview` from CI. A preview reads the state, decrypts its secrets
 * with the stack's KMS key, takes the state lock, and asks Google to describe
 * what exists; it applies nothing. `viewer` on the project is read-only
 * everywhere and does not include reading secret payloads; `objectUser` on
 * the state bucket is what the lock file needs; `cryptoKeyDecrypter` on the
 * one key, not the key ring. The deployer still cannot `pulumi up`.
 */
new gcp.projects.IAMMember('deployer-can-read-project', {
  project,
  role: 'roles/viewer',
  member: pulumi.interpolate`serviceAccount:${deployAccount.email}`,
})

new gcp.storage.BucketIAMMember('deployer-can-lock-state', {
  bucket: stateBucket,
  role: 'roles/storage.objectUser',
  member: pulumi.interpolate`serviceAccount:${deployAccount.email}`,
})

new gcp.kms.CryptoKeyIAMMember('deployer-can-decrypt-secrets', {
  cryptoKeyId: secretsKey,
  role: 'roles/cloudkms.cryptoKeyDecrypter',
  member: pulumi.interpolate`serviceAccount:${deployAccount.email}`,
})

// ---------------------------------------------------------------------------
// Optional custom domain
// ---------------------------------------------------------------------------

/**
 * Domain mapping is only created when a domain is configured, because it fails
 * unless the domain has already been verified in Search Console — a manual,
 * human step that cannot be automated from here. Runbook 03 covers it.
 */
const domainMapping = customDomain
  ? new gcp.cloudrun.DomainMapping(
      'domain',
      {
        project,
        location: region,
        name: customDomain,
        metadata: { namespace: project, labels: tags },
        spec: { routeName: service.name },
      },
      dependsOnApis,
    )
  : undefined

// ---------------------------------------------------------------------------
// Budget
// ---------------------------------------------------------------------------

/**
 * The alert that wakes someone up. `maxInstances` bounds compute, but Cloud
 * SQL bills while idle and nothing else here has a ceiling, so a monthly
 * budget on this stack's project is the one control that notices a mistake
 * in dollars rather than in resources.
 *
 * Budgets live on the billing account, not the project, so the operator who
 * applies this needs Billing Account Costs Manager (or Administrator) on it
 * (runbook 01). The verify gate only previews and never reads the budget
 * API, so the deployer needs no billing role. No `allUpdatesRule`: the
 * provider then requires a channel or topic, whereas leaving it out keeps the
 * API default, which emails billing-account administrators and users at each
 * threshold with nothing extra to keep alive.
 */
const projectInfo = gcp.organizations.getProjectOutput({ projectId: project })

new gcp.billing.Budget(
  'budget',
  {
    billingAccount,
    displayName: `${serviceName}-${environment}`,
    budgetFilter: {
      projects: [pulumi.interpolate`projects/${projectInfo.number}`],
      calendarPeriod: 'MONTH',
    },
    amount: {
      specifiedAmount: { currencyCode: 'USD', units: String(budgetAmount) },
    },
    thresholdRules: [
      { thresholdPercent: 0.5 },
      { thresholdPercent: 0.9 },
      { thresholdPercent: 1.0 },
      { thresholdPercent: 1.0, spendBasis: 'FORECASTED_SPEND' },
    ],
  },
  dependsOnApis,
)

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
//
// The first four are exactly the values GitHub needs as repository variables;
// runbook 01 copies them across.

export const serviceUrl = service.uri
export const imageRepository = pulumi.interpolate`${region}-docker.pkg.dev/${project}/${repository.repositoryId}`
export const imageName = pulumi.interpolate`${region}-docker.pkg.dev/${project}/${repository.repositoryId}/${serviceName}`

/** `WIF_PROVIDER` in GitHub. */
export const workloadIdentityProvider = provider.name
/** `DEPLOY_SERVICE_ACCOUNT` in GitHub. */
export const deployServiceAccount = deployAccount.email
/** `CLOUD_RUN_SERVICE` / `ARTIFACT_REPO` / `GCP_REGION` in GitHub. */
export const cloudRunService = service.name
export const artifactRepository = repository.repositoryId
export const gcpRegion = region
export const gcpProject = project

export const runtimeServiceAccount = runtimeAccount.email

/** `API_CLOUD_RUN_SERVICE` / `API_MIGRATION_JOB` in GitHub, for cd-api.yml. */
export const apiCloudRunService = apiService.name
export const apiMigrationJob = migrateJob.name
export const apiServiceUrl = apiService.uri

/** The api's identity, database and secret, for runbook 06. */
export const apiRuntimeServiceAccount = apiRuntimeAccount.email
export const databaseInstanceConnectionName = dbInstance.connectionName
export const databaseUrlSecretId = databaseUrlSecret.secretId
export const customDomainStatus = domainMapping
  ? domainMapping.statuses.apply((s) => s?.[0]?.resourceRecords ?? 'pending')
  : pulumi.output('not configured')
