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

const config = new pulumi.Config('reward-app')
const gcpConfig = new pulumi.Config('gcp')

const project = gcpConfig.require('project')
const region = gcpConfig.get('region') ?? 'us-central1'
const serviceName = config.get('serviceName') ?? 'reward-app'
const minInstances = config.getNumber('minInstances') ?? 0
const maxInstances = config.getNumber('maxInstances') ?? 4
const customDomain = config.get('customDomain') ?? ''

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
    // it, every preview proposes removing it.
    ignoreChanges: ['template.containers[0].image', 'client', 'clientVersion', 'scaling'],
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
export const customDomainStatus = domainMapping
  ? domainMapping.statuses.apply((s) => s?.[0]?.resourceRecords ?? 'pending')
  : pulumi.output('not configured')
