# terraform-platform

> **Current setup (fresh `dbxp` setup in the existing VPC):** follow [docs/SETUP-existing-vpc.md](docs/SETUP-existing-vpc.md).
> Other teams and prod examples are in `docs/examples/`; copy them into `workspace-level/` when ready.

Databricks on AWS for several teams, each with its own **dev** and **prod** workspace,
inside an **existing VPC** owned by the client's CloudOps team.

| Exists already (CloudOps)                        | Created by this repo                                        |
|--------------------------------------------------|-------------------------------------------------------------|
| VPC, route tables, NAT / TGW egress              | Security group per workspace (Databricks rules)             |
| Private subnets per workspace (2 AZs) *          | Cross-account IAM role ** + root S3 bucket                  |
| VPC endpoints (S3 gateway, STS, Kinesis)         | Workspace, metastore assignment, workspace permissions      |
| Databricks account, metastore ***, account groups| UC bucket + IAM role, storage credential, external location |
|                                                  | Catalogs, schemas, grants, cross-team read-only shares      |
|                                                  | Job cluster policies                                        |

\* or let Terraform create subnets in free VPC space (`network.new_subnets`)
\** or pass one CloudOps created (`cross_account_role_arn`)
\*** or create it here (`account-level/account.tfvars`, `metastore.create = true`)

## Layout

```
terraform-platform/
├── bootstrap/                  # once per AWS account, by hand: state bucket + GitHub OIDC roles
├── modules/                    # reusable building blocks (no providers, no state)
│   ├── workspace-network/      #   existing VPC/subnets lookup + SG (+ optional new subnets)
│   ├── databricks-workspace/   #   cross-account role, root bucket, mws configs, workspace
│   ├── unity-catalog/          #   UC storage, catalogs, schemas, grants, shares
│   └── cluster-policies/       #   job-cluster policies + CAN_USE
├── account-level/              # ONE state: metastore (new or existing), admin group, groups
│   ├── main.tf  variables.tf  outputs.tf  backend.tf
│   └── account.tfvars
├── workspace-level/
│   ├── _template/              # the code every team runs (two roots, identical variables.tf)
│   │   ├── workspace/          #   state: workspace/<team>/<env>/terraform.tfstate
│   │   └── config/             #   state: workspace-config/<team>/<env>/terraform.tfstate
│   ├── de/        dev.tfvars  prod.tfvars
│   ├── ds/        dev.tfvars  prod.tfvars
│   └── elections/ dev.tfvars  prod.tfvars
├── scripts/
│   ├── tf.sh                   # plan (saved) / apply-saved / apply, layer by layer
│   ├── changed-targets.sh      # which team/env a change touches
│   └── plan-summary.sh         # plan table for the run summary
└── .github/
    ├── workflows/pr-plan.yml       # 1: PR -> plan dev + prod for changed teams (comment)
    ├── workflows/deploy.yml        # 2: merge -> dev plan+deploy -> prod plan -> [approve] -> prod deploy
    ├── workflows/promote-prod.yml  # 3: apply a run's saved prod plans (when no reviewer gate)
    └── actions/{tf-setup,plan-comment}/
```

Teams do **not** copy Terraform code. A team is two tfvars files; everyone runs
`_template`. A fix in a module reaches every team on the next run, and nothing drifts.

Two roots per team/env, not one, because the `config` root needs the workspace URL
for its provider. That URL only exists after the `workspace` root is applied.

## Pipeline

```
 PR opened ──> 1-pr-plan     lint ─> changed targets ─> plan dev + prod per team (read-only, no lock) ─> PR comments
                                                                                        │
 merge to main ──> 2-deploy  account (if changed)                                      ▼
                               └─> DEV   per team: plan ─> deploy                 (automatic)
                                     └─> PROD  per team: plan, saved as artifact  (read-only role)
                                           └─> approval ─> PROD deploy of the SAVED plan
                                                 │
                                                 ├─ PROD_GATE=reviewers : 'prod' environment reviewers approve in the run
                                                 └─ otherwise (default)  : run '3-promote-prod' with the run ID
```

- **Dev first, always.** Prod is only planned after every dev target in the run succeeded.
- **Prod applies exactly what was approved.** The prod plan is saved as a run artifact
  and applied with `terraform apply <planfile>`. If prod changed in between, Terraform
  refuses ("saved plan is stale"); re-run `2-deploy`. Plan artifacts are kept 7 days and
  can be read by anyone with read access to the repo, so keep the repo private.
- **Only teams with prod changes** go to approval; "No changes" teams are skipped.
- **Re-deploy a team** (drift, new team, retry): Actions → 2-deploy → Run workflow → team `de`.
- A brand-new workspace has no state when prod is planned, so its `config` layer is
  planned and applied right after the workspace, inside the approved job. This happens
  only on the first deploy of that team.

### How teams deploy without conflicts

| Risk | What prevents it |
|---|---|
| Two teams overwrite each other's state | Separate state per team/env/layer: `workspace/<team>/<env>`, `workspace-config/<team>/<env>` |
| Two runs apply the same team at once | Job concurrency group `tf-<team>-<env>` (queued, never cancelled) + S3 state lock |
| One team waits for another team | No workflow-wide lock; each team/env is its own matrix job (max 4 in parallel) |
| One team's failure blocks others | `fail-fast: false`: other teams' dev deploys finish. Prod waits until all dev targets pass |
| PR plans block a deploy | PR and prod plans run with `-lock=false` (read-only) |
| Team A edits team B | CODEOWNERS: each team owns `workspace-level/<team>/`, platform owns modules/template |
| Shared module change surprises everyone | It plans **every** team on the PR, deploys all dev, then prod with approval |
| Account-level (metastore) changes | Own job + own lock group `tf-account`, runs before any team |

Two merges in a row: the second run's jobs queue behind the first for the same team.
If the first run's prod is still waiting for approval, approve or reject it first.
Otherwise the second run's plan goes stale.

## What CloudOps must give you per workspace

For each team/env (e.g. `de` `dev`):

- **VPC ID** (same VPC for all teams is fine). DNS hostnames + DNS resolution enabled.
- **2 private subnets in 2 different AZs**, for this workspace only. Size: /17 to /26.
  Databricks uses **2 IPs per node**, so a /23 (≈ 251 nodes per subnet) suits most job workloads.
- **Egress** from those subnets through NAT / TGW / firewall to the Databricks control plane
  (443, 8443-8451), S3, STS and Kinesis, plus 3306 if you use the legacy Hive metastore.
- Optional: an existing **security group** (`network.security_group_id`). Otherwise one is created.
- Optional: an existing **cross-account role** ARN. To have CloudOps create it, run a plan
  and hand them the `cross_account_trust_json` and `cross_account_policy_json` outputs of the
  workspace module.

Subnets are checked at plan time: at least 2 AZs, all in the given VPC.

## Prerequisites

| # | What | Who | Notes |
|---|---|---|---|
| 1 | AWS account ID, region (us-east-1) | CloudOps | Confirm SCPs allow EC2 SG, IAM roles `dbx-*`, S3 buckets `dbx-*` |
| 2 | VPC ID + 2 private subnets per team per env (2 AZs) | CloudOps | Egress to Databricks control plane, S3, STS, Kinesis (see above) |
| 3 | An admin identity for the one-time bootstrap | CloudOps | Assumed role or SSO; no root, no access keys |
| 4 | Databricks account ID | Account admin | Account console → top-right |
| 5 | Service principal, **account admin**, OAuth secret | Account admin | Used by CI (`DATABRICKS_CLIENT_ID/SECRET`) |
| 6 | Account groups: `dbr-platform-admins`, `dbr-<team>-admins/engineers/analysts` | IdP/SCIM team | Or create them in `account-level/account.tfvars` |
| 7 | Existing metastore name in the region, or approval to create one | Account admin | One metastore per region per account |
| 8 | GitHub repo `terraform-platform` + 2 environments | You | Org/repo **numeric IDs** for the OIDC trust (`gh api repos/<org>/<repo> --jq .id`) |
| 9 | Prod approvers | Client | Required reviewers need a public repo or GitHub Team/Enterprise; otherwise use `3-promote-prod` |
| 10 | Terraform ≥ 1.11, AWS CLI v2, git | You | For bootstrap only; everything else runs in CI |

## Setup, step by step

1. **Bootstrap AWS** (once, from your machine with the admin identity):
   ```powershell
   cd bootstrap
   copy terraform.tfvars.example terraform.tfvars   # github_org, github_repo, github_owner_id, github_repo_id
   terraform init
   terraform apply
   terraform output                                 # note the state bucket + 3 role ARNs
   ```
   Then uncomment the backend in `bootstrap/versions.tf` and run `terraform init -migrate-state`.
   Already ran bootstrap for another repo in this account? Re-apply with this repo's name and IDs.
   The trust is per repo, and this version also lets the read-only plan role run on `main`.

2. **GitHub → Settings → Environments**: create `dev` and `prod`.
   - Both: variable `AWS_APPLY_ROLE_ARN` = `dbx-gha-apply-dev` / `dbx-gha-apply-prod` ARN.
   - Both: *Deployment branches* → **Selected branches: `main`**.
   - `prod`: *Required reviewers* = approvers (if your plan supports it).

3. **GitHub → Settings → Secrets and variables → Actions**
   - Variables: `AWS_REGION`, `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `DATABRICKS_ACCOUNT_ID`,
     `PROD_GATE` = `reviewers` (only if step 2 reviewers exist; leave unset otherwise).
   - Secrets: `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`. Type them into GitHub directly.

4. **Branch protection on `main`**: require a PR, require `1-pr-plan` checks to pass, and
   require Code Owner review (update `.github/CODEOWNERS` with real teams).

5. **Fill the values**: `account-level/account.tfvars` (metastore), then each
   `workspace-level/<team>/<env>.tfvars` (VPC, subnets, groups, catalogs).

6. **First deploy**: open a PR with those values and read the plan comments. Merge.
   `2-deploy` applies account → dev for all teams → plans prod.

7. **Prod**: approve in the run (`PROD_GATE=reviewers`), or run **3-promote-prod** with
   the run ID shown in the `2-deploy` summary.

8. **Check**: workspace URLs are in the job logs (`terraform output`). Log in as a member
   of `dbr-platform-admins` and check the catalogs, schemas and cluster policy.

9. Optional: commit `workspace-level/_template/*/.terraform.lock.hcl` and `account-level/.terraform.lock.hcl`
   after the first run (`terraform providers lock -platform=linux_amd64 -platform=windows_amd64`),
   so provider upgrades also go through PRs.

## Day to day

| You want to… | Do this |
|---|---|
| Change DE grants | Edit `workspace-level/de/*.tfvars` → PR (plans `de-dev`, `de-prod`) → merge → dev deploys → approve prod |
| Change only dev | Edit only `dev.tfvars`: prod plan is not run for that team |
| Change a module / template | PR plans every team → merge → all dev → all prod with changes → approve |
| Redeploy one team | 2-deploy → Run workflow → team |
| Run locally | `bash scripts/tf.sh plan de dev` (same env vars as CI) |

## Add a team (e.g. `analytics`)

1. CloudOps: 2 subnets per environment (2 AZs each) in the shared VPC.
2. Create the account groups (`dbr-analytics-*`) in the IdP / SCIM, or list them in
   `account-level/account.tfvars`.
3. `mkdir workspace-level/analytics`, then copy `de/dev.tfvars` and `de/prod.tfvars` and change
   `team`, the subnets, groups and catalog names (`dev_analytics`, `prod_analytics`).
4. Add a CODEOWNERS line. Open a PR and merge. Dev deploys; run the workflow for prod.

## Cross-team read access

In the **producer's** tfvars:

```hcl
catalogs = {
  prod_de = {
    ...
    consumers = {
      ds = { groups = ["dbr-ds-engineers", "dbr-ds-analysts"], schemas = ["gold"] }
    }
  }
}
```

This binds `prod_de` **read-only** to the DS prod workspace, then grants USE CATALOG, USE
SCHEMA and SELECT on `gold` to those groups. Catalogs are ISOLATED, so nothing is visible
anywhere else.

## What Terraform manages vs the UI

Terraform owns catalogs, schemas, storage, bindings and **group-level** grants on catalogs
and schemas. Grants are non-authoritative (`databricks_grant`). Catalog and schema owners can still add
table-level or individual grants in the UI, and Terraform won't remove them. Tables
and pipelines are deployed with Databricks Asset Bundles, not here.

## Removing a team

Deleting a tfvars file does **not** destroy anything; CI ignores deleted files. Destroy
by hand first (`config`, then `workspace`). Schemas use `force_destroy = false`, so
schemas that hold tables won't be dropped.
