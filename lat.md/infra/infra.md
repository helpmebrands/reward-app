# Infra

The platform: how the repository is verified and deployed, the Pulumi program and the tests that pin its configuration and the repository's shape.

- [[deployment]] — CI/CD, the Pulumi-owns-shape / CI-owns-image rule, the container, cache and security headers, infrastructure including the database, its secret and the KMS-guarded state.
- [[infra-tests]] — Pulumi config, runbooks, workflows, the monorepo layout and this graph's shape.
