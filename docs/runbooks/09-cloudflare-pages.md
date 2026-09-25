# 09 — Cloudflare Pages

How the static site in `apps/site` gets onto the web: a Cloudflare Pages
project per environment, a custom domain on it, and the token `cd.yml`
deploys with. **Do it once per environment, top to bottom, in this order.**
Every numbered step can be done as soon as the step above it is finished.

| Git branch | Pulumi stack | GitHub environment | Pages project | URL |
| --- | --- | --- | --- | --- |
| `develop` | `staging` | `staging` | `helpmereward-staging` | <https://staging.helpmereward.com> |
| `main` | `prod` | `prod` | `helpmereward` | <https://helpmereward.com> |

Each Pages project's *production branch* is the git branch that deploys to
it, so every deploy is a production deployment of its own project, and the
custom domain sits on that project without branch aliases. `cd.yml` uploads
`apps/site/public` as it is; Pages builds nothing.

## What you will end up with

| What | Made by | Stored in |
| --- | --- | --- |
| Pulumi's Cloudflare token (Pages and DNS edit) | you, in the Cloudflare dashboard | stack config `cloudflare:apiToken`, encrypted |
| The account id and the `helpmereward.com` zone id | read from the dashboard | stack config `cloudflareAccountId`, `cloudflareZoneId` |
| The Pages project, its custom domain and a proxied CNAME | `pulumi up` | Cloudflare |
| `CLOUDFLARE_ACCOUNT_ID`, `PAGES_PROJECT`, `SITE_URL`, `SECRET_CLOUDFLARE_API_TOKEN` | `pulumi up` | the GitHub environment named after the stack |
| The deploy token (Pages edit only) | you, in the Cloudflare dashboard | Secret Manager `reward-app-cloudflare-api-token-<stack>` |

Two tokens, for a reason: the one `cd.yml` holds can only upload to Pages,
so a leaked workflow cannot touch DNS. The one Pulumi holds can edit DNS and
Pages, and the `infra` job's preview decrypts it too, the way it decrypts
`github:token`; a preview reads and never writes.

## Before you start

| Need | Check |
| --- | --- |
| [01 — Initial deployment](01-initial-deployment.md) is done for the stack | `pulumi stack ls` in `infra/` lists it |
| *Super Administrator* on the Cloudflare account that holds `helpmereward.com` | the zone shows as **Active** at <https://dash.cloudflare.com> |
| Owner on the Google Cloud project | `gcloud projects get-iam-policy "$PROJECT_ID"` lists you |
| `gcloud`, `pulumi`, `dig` and `curl` | each answers `--version` (`dig -v`) |

Open a terminal in the repository and set these once. Every command below
uses them; for production use `helpme-reward-prod` (or the prod project id)
and `prod`.

```sh
$ export PROJECT_ID=helpme-reward-staging
$ export STACK=staging
$ cd infra
$ pulumi stack select "$STACK"
```

## Part 1 — Pulumi's token and the ids

1. Open <https://dash.cloudflare.com/profile/api-tokens>.
2. Click **Create Token**.
3. Next to *Create Custom Token*, click **Get started**.
4. Token name: `Pulumi reward-app <stack>`, for example `Pulumi reward-app staging`.
5. Under *Permissions*, add two rows:
   - `Account` · `Cloudflare Pages` · `Edit` (written `Cloudflare Pages:Edit` below)
   - `Zone` · `DNS` · `Edit` (written `DNS:Edit` below)
6. Under *Account Resources*: `Include` · the account that holds `helpmereward.com`.
7. Under *Zone Resources*: `Include` · `Specific zone` · `helpmereward.com`.
8. Leave *Client IP Address Filtering* empty and *TTL* unset.
9. Click **Continue to summary**.
10. Click **Create Token**.
11. Copy the token. Cloudflare shows it once.
12. Store it on the stack. Paste the token when prompted:

    ```sh
    $ pulumi config set --secret cloudflare:apiToken
    ```

13. Open <https://dash.cloudflare.com>, click the `helpmereward.com` zone,
    and scroll the *Overview* page to the *API* box on the right.
14. Store the two ids it shows:

    ```sh
    $ pulumi config set reward-app:cloudflareAccountId <Account ID>
    $ pulumi config set reward-app:cloudflareZoneId <Zone ID>
    ```

15. Set the site's domain, project and branch. Staging already commits these
    in `Pulumi.staging.yaml`; `pulumi config` prints them, so this step only
    changes a new stack:

    ```sh
    $ pulumi config set reward-app:customDomain staging.helpmereward.com      # prod: helpmereward.com
    $ pulumi config set reward-app:pagesProject helpmereward-staging          # prod: helpmereward
    $ pulumi config set reward-app:siteBranch develop                         # prod: main
    ```

16. Commit `infra/Pulumi.<stack>.yaml`. The token is encrypted in it; the
    ids are not secret.

## Part 2 — Clear the way for the record

Pulumi creates the site's CNAME. A record by the same name that Pulumi did
not create makes the apply fail with *An A, AAAA, or CNAME record with that
host already exists*.

1. List what the name holds now:

   ```sh
   $ dig +short staging.helpmereward.com        # prod: dig +short helpmereward.com
   ```

2. If it prints nothing, go to Part 3.
3. Open the zone's **DNS** → **Records** page in the dashboard.
4. Find the record whose *Name* is `staging` (prod: `helpmereward.com`, the apex).
5. Click **Edit** on it.
6. Click **Delete**.
7. Confirm with **Delete**.

The site is unreachable from this step to the end of Part 4, a few minutes.

## Part 3 — Apply

1. Preview. Expect a `cloudflare:index/pagesProject:PagesProject`, a
   `PagesDomain`, a `DnsRecord`, a Secret Manager secret
   `signing-cloudflare-api-token` with its IAM member, and four GitHub
   environment variables to be created:

   ```sh
   $ pulumi preview --diff
   ```

2. Apply with the quota project override (runbook 01 §4 says why):

   ```sh
   $ USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT="$PROJECT_ID" pulumi up
   ```

3. Read what Pages named the project's own address:

   ```sh
   $ pulumi stack output pagesSubdomain          # helpmereward-staging.pages.dev
   ```

## Part 4 — The deploy token and the first deploy

1. Open <https://dash.cloudflare.com/profile/api-tokens>.
2. Click **Create Token**.
3. Next to *Create Custom Token*, click **Get started**.
4. Token name: `reward-app deploy <stack>`, for example `reward-app deploy staging`.
5. Under *Permissions*, add one row: `Account` · `Cloudflare Pages` · `Edit`.
6. Under *Account Resources*: `Include` · the account that holds `helpmereward.com`.
7. Click **Continue to summary**.
8. Click **Create Token**.
9. Copy the token.
10. Add it as the secret's first version. `read -rs` waits for you to paste
    the token and press Enter, and keeps it off the screen and out of your
    shell history:

    ```sh
    $ read -rs CF_TOKEN; printf '%s' "$CF_TOKEN" | gcloud secrets versions add reward-app-cloudflare-api-token-staging \
        --project "$PROJECT_ID" --data-file -
    ```

    For prod the secret is `reward-app-cloudflare-api-token-prod`.

11. Deploy the branch by hand once:

    ```sh
    $ gh workflow run cd.yml --ref develop      # prod: --ref main
    $ gh run watch
    ```

**Verify:**

```sh
$ curl -sS -o /dev/null -w '%{http_code}\n' https://staging.helpmereward.com/        # 200
$ curl -sS -o /dev/null -w '%{http_code}\n' https://staging.helpmereward.com/nope    # 404
$ curl -sSI https://staging.helpmereward.com/ | grep -i content-security-policy     # script-src 'none'
$ pulumi preview                                                                     # no changes
```

The dashboard's **Workers & Pages** → `helpmereward-staging` →
**Custom domains** tab shows `staging.helpmereward.com` as **Active**. A
fresh domain can sit at *Verifying* for a few minutes while Cloudflare
issues its certificate, and the 200 above fails while it does.

## Part 5 — Production and `main`

Production has no stack yet. When it does:

1. Create the `prod` stack and its project with [01](01-initial-deployment.md)
   and [03 — Adding a production environment](03-infrastructure-change.md#adding-a-production-environment).
2. Run Parts 1 to 4 of this runbook with `STACK=prod`, the prod project id,
   `helpmereward.com`, `helpmereward` and `main`. The apex CNAME is fine:
   Cloudflare flattens a CNAME at the zone apex.
3. Create `main` from `develop` and push it. The push runs `cd.yml` in the
   `prod` environment and deploys to <https://helpmereward.com>:

   ```sh
   $ git fetch origin
   $ git push origin origin/develop:refs/heads/main
   ```

4. Add a ruleset for `main` in `infra-repo/` (today it protects only
   `develop`) so `main` moves only by pull request.

## Rolling the site back

A Pages rollback is a pointer move, like a Cloud Run traffic shift:

1. Open **Workers & Pages** → the project → **Deployments**.
2. Find the last good production deployment. Its commit hash is the
   `--commit-hash` `cd.yml` passed.
3. Click its **⋯** menu.
4. Click **Rollback to this deployment**.
5. Confirm with **Rollback**.
6. Revert the bad commit on the branch, as [04](04-rollback.md#then-get-develop-back-to-the-truth)
   describes, so the next merge does not redeploy it.

## Rotating a token

1. Create the replacement exactly as Part 1 steps 1 to 11 (Pulumi's) or
   Part 4 steps 1 to 9 (the deploy token) describe.
2. Store it: `pulumi config set --secret cloudflare:apiToken` for Pulumi's,
   or Part 4 step 10 for the deploy token (a new version; `cd.yml` reads
   `latest`).
3. Run `pulumi preview` (Pulumi's) or `gh workflow run cd.yml --ref develop`
   (the deploy token) and check it passes.
4. In <https://dash.cloudflare.com/profile/api-tokens>, click the old
   token's **⋯** menu.
5. Click **Delete** and confirm.
