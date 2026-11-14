# terraform-platform

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
│   ├── tf.sh                   # init (partial backend) + plan/apply in order
│   └── changed-targets.sh      # which team/env a change touches
└── .github/
    ├── workflows/plan.yml      # PR: plan only what changed, one comment per target
    ├── workflows/apply.yml     # merge: dev; manual run: prod
    └── actions/plan-comment/
```

Teams do **not** copy Terraform code. A team is two tfvars files; everyone runs
`_template`. A fix in a module reaches every team on the next run, and nothing drifts.

Two roots per team/env, not one, because the `config` root needs the workspace URL
for its provider. That URL only exists after the `workspace` root is applied.

## Order of things

```
bootstrap (by hand, once)
   └─> account-level            metastore id
          └─> workspace  (per team/env)   workspace id + URL
                 └─> config  (per team/env)   catalogs, grants, policies, shares
```

`apply.yml` runs **account → all workspaces → all configs**, so a share from DE prod
to DS prod always finds the DS prod workspace. If a consumer workspace doesn't exist
yet, the plan shows a warning ("Read-only share pending …"). The share is created on
the next run.

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

## One-time setup

1. **Bootstrap** (your laptop, admin credentials for the target AWS account):
   ```powershell
   cd bootstrap
   copy terraform.tfvars.example terraform.tfvars   # set github_org/repo, owner/repo IDs
   terraform init; terraform apply
   ```
   Then uncomment the backend in `bootstrap/versions.tf` and `terraform init -migrate-state`.
   Reusing an AWS account from an earlier repo? Re-apply bootstrap with this repo's
   `github_repo`, `github_owner_id` and `github_repo_id`. The OIDC trust is per repo.

2. **GitHub**: environments `dev` and `prod`, each with variable `AWS_APPLY_ROLE_ARN`.
   Repo variables `AWS_REGION`, `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `DATABRICKS_ACCOUNT_ID`.
   Repo secrets `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET` (account-admin service
   principal, OAuth M2M). Type secrets straight into GitHub. Never paste them in chat or commit them.

3. **Account level**: fill in `account-level/account.tfvars`. If the client already has
   a metastore in the region, use `create = false` and its exact name.
   Run **Actions → terraform-apply → Run workflow** with `account` ticked.

4. **Teams**: replace the `vpc-<…>` / `subnet-<…>` placeholders and group names in each
   `workspace-level/<team>/<env>.tfvars`. Open a PR and review the plans. Merge to deploy dev.

## Day to day

| You want to…                     | Do this                                                                 |
|----------------------------------|-------------------------------------------------------------------------|
| Change DE dev grants             | Edit `workspace-level/de/dev.tfvars` → PR (plans `de-dev` only) → merge   |
| Ship to prod                     | Actions → terraform-apply → Run workflow → `prod`, team `de` (or `all`)  |
| Change a module                  | PR plans **every** team/env; merge applies all **dev**; prod by hand     |
| Run locally                      | `bash scripts/tf.sh plan de dev` (needs the same env vars as CI)         |

Prod never deploys on merge. On GitHub Free private repos, environment reviewers aren't
available, so the manual run is the gate. Add required reviewers to `prod` if your plan
supports them.

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
