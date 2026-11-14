# From scratch: new workspace `dbxp-dev-de` in the existing VPC

A fully separate setup next to the first one (`dbx-*`). Only two things are shared:

| Shared (must be) | Why |
|---|---|
| VPC `vpc-03950e5934415cd3c` (NAT, S3/STS/Kinesis endpoints) | Your choice |
| Metastore `metastore-us-east-1` | Databricks allows **one metastore per region per account** |
| GitHub OIDC provider in AWS | AWS allows one per account (the roles are new) |

Everything else is new, prefixed `dbxp`:

| Layer | New resources |
|---|---|
| CI/CD | State bucket `dbxp-tfstate-473640421776-us-east-1`, roles `dbxp-gha-plan`, `dbxp-gha-apply-dev/prod`, service principal `dbxp-deployer` |
| Account | Groups `dbxp-platform-admins`, `dbxp-de-admins/engineers/analysts` |
| Network | Subnets 10.10.64.0/20 (1a), 10.10.80.0/20 (1b), SG `dbxp-dev-de-workspace`, 443 rule into the endpoint SG |
| Workspace | `dbxp-dev-de`, cross-account role, root bucket, network/storage/credential configs |
| Unity Catalog | Bucket + role `dbxp-dev-de-uc-*`, storage credential, external location, catalog `dbxp_dev_de` (bronze/silver/gold), grants |
| Compute | Cluster policy `dbxp-dev-de-jobs` |

The old setup (`dbx-dev` workspace, `dbx-*` roles and state) keeps working untouched.

Commands are PowerShell. Values in `<…>` are yours to fill in.

---

## Step 0: Tools and sign-in

```powershell
terraform version          # 1.11 or newer
aws --version              # v2
gh auth status             # GitHub CLI signed in as brata-spec
aws sts get-caller-identity   # sign in like last time; Account must be 473640421776
```

## Step 1: Look at the VPC (2 values + 1 check)

```powershell
$VPC = "vpc-03950e5934415cd3c"

# a) Used address ranges. 10.10.64.0/20 and 10.10.80.0/20 must not be in this list.
aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC `
  --query "Subnets[].[SubnetId,AvailabilityZone,CidrBlock]" --output table

# b) Private route tables (named ...-private-us-east-1a / -1b, route 0.0.0.0/0 -> nat-...)
aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC `
  --query "RouteTables[].[RouteTableId,Tags[?Key=='Name']|[0].Value]" --output table

# c) S3 gateway endpoint policy
aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC Name=vpc-endpoint-type,Values=Gateway `
  --query "VpcEndpoints[].PolicyDocument" --output text
```

- Put the two **private** route table IDs into `workspace-level/de/dev.tfvars` (`route_table_ids`).
- c): if the policy says `"Resource": "*"`, you're fine. If it lists buckets (`AllowApprovedBucketsOnly`),
  the new buckets would be blocked. Add them in the **old** repo's `envs/dev/workspace.tfvars`
  and deploy it once:
  `extra_allowed_s3_buckets = ["dbxp-dev-de-root-473640421776", "dbxp-dev-de-uc-473640421776"]`

## Step 2: New service principal (Databricks account console)

1. Account console → **User management → Service principals → Add**, name `dbxp-deployer`.
2. Open it → **Roles** → turn on **Account admin**.
3. **Credentials & secrets → OAuth secrets → Generate secret**. Keep the Client ID + Secret
   open in that window, because you'll paste them into GitHub in step 5. Don't save them in a file or chat.

## Step 3: GitHub repo

```powershell
gh repo create brata-spec/terraform-platform --private
gh api repos/brata-spec/terraform-platform --jq .id        # repo id -> next step
```

## Step 4: Bootstrap (new state bucket + new CI roles)

```powershell
cd terraform-platform\bootstrap
copy terraform.tfvars.example terraform.tfvars    # put the repo id in github_repo_id
terraform init
terraform plan        # expect: bucket + bucket settings + 3 roles + policies; NO OIDC provider
terraform apply
terraform output      # state_bucket, plan_role_arn, apply_role_arns
```

Move the bootstrap state into its new bucket. In `bootstrap\versions.tf`, uncomment the `backend "s3"` block, then:

```powershell
terraform init -migrate-state      # answer yes
Remove-Item terraform.tfstate*     # the copy now lives in S3
cd ..
```

## Step 5: GitHub settings

```powershell
$R = "brata-spec/terraform-platform"
gh variable set AWS_REGION            -R $R --body "us-east-1"
gh variable set TF_STATE_BUCKET       -R $R --body "dbxp-tfstate-473640421776-us-east-1"
gh variable set AWS_PLAN_ROLE_ARN     -R $R --body "arn:aws:iam::473640421776:role/dbxp-gha-plan"
gh variable set DATABRICKS_ACCOUNT_ID -R $R --body "<databricks-account-id>"

gh secret set DATABRICKS_CLIENT_ID     -R $R    # paste dbxp-deployer Client ID
gh secret set DATABRICKS_CLIENT_SECRET -R $R    # paste the secret (hidden input)

foreach ($e in "dev","prod") {
  gh api -X PUT "repos/$R/environments/$e" | Out-Null
  gh variable set AWS_APPLY_ROLE_ARN -R $R --env $e --body "arn:aws:iam::473640421776:role/dbxp-gha-apply-$e"
}
```

## Step 6: Push the code, without the team yet (PR #1 = account level)

The workspace's catalogs need metastore rights that only a metastore admin can grant (step 7).
So deploy the account level (groups) first.

```powershell
git init; git branch -M main
git add README.md; git commit -m "init"
git remote add origin https://github.com/brata-spec/terraform-platform.git
git push -u origin main

git checkout -b platform
git add .
git reset workspace-level/de/dev.tfvars            # keep the team for PR #2
git commit -m "Platform code + account level"
git push -u origin platform
gh pr create --fill
```

PR checks: **1-pr-plan** → `account` comment: 4 groups + 1 group membership to add, metastore only read.
Merge it:

```powershell
gh pr merge --squash --delete-branch
gh run watch            # 2-deploy: account deploy only
```

## Step 7: Give the new admin group rights on the metastore (one-time, by hand)

You must be a metastore admin (member of `dbr-platform-admins`; check under Account console → User management → Groups).
Open the **old** `dbx-dev` workspace → SQL editor (or a notebook) and run:

```sql
GRANT CREATE CATALOG, CREATE STORAGE CREDENTIAL, CREATE EXTERNAL LOCATION
ON METASTORE TO `dbxp-platform-admins`;
```

Also add yourself to `dbxp-platform-admins` and `dbxp-de-engineers` (Account console → Groups),
so you can log in to the new workspace.

## Step 8: Add the team (PR #2 = workspace + catalog)

```powershell
git checkout main; git pull
git checkout -b de-dev
git add workspace-level/de/dev.tfvars
git commit -m "DE dev workspace"
git push -u origin de-dev
gh pr create --fill
```

`de-dev` comment, expected:
- `workspace-de-dev`: 2 subnets, 2 route table associations, SG + rules, 443 rule into the endpoint SG,
  cross-account role, root bucket, workspace, metastore assignment and permissions.
- `config-de-dev`: *Skipped* (the workspace doesn't exist yet). It's planned and applied right after the workspace.

```powershell
gh pr merge --squash --delete-branch
gh run watch            # 2-deploy: dev de -> workspace, then config. No prod targets.
```

## Step 9: Check

- Workspace URL: the `dev de` job log (`workspace_url`), or Account console → Workspaces → `dbxp-dev-de`.
- Account console → Catalog → `metastore-us-east-1` → Workspaces lists `dbx-dev` and `dbxp-dev-de`.
- New workspace → Catalog: `dbxp_dev_de` with bronze/silver/gold. It is not visible from `dbx-dev` (catalog is isolated).
- Compute → Policies: `dbxp-dev-de-jobs`.
- **Network test:** create a job with a small notebook (`spark.range(10).show()`) on that policy and run it.
  If the cluster reaches *Running* and the job succeeds, the subnets, NAT, STS and S3 paths all work.

## If something fails

| Symptom | Likely cause |
|---|---|
| CI: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Wrong `github_repo_id`, or the repo uses immutable OIDC subjects: re-check step 4 values |
| CI: `invalid_client` / `cannot configure default credentials` | Client ID/secret in GitHub don't match `dbxp-deployer` |
| `PERMISSION_DENIED ... CREATE STORAGE CREDENTIAL` | Step 7 not done |
| `InvalidSubnet.Conflict` | 10.10.64.0/20 or 10.10.80.0/20 already used: change them in dev.tfvars |
| Cluster stuck "Pending"/bootstrap timeout | Wrong route table in step 1, or S3 endpoint allowlist (step 1c) |

## Later: prod

Copy `docs/examples/workspace-level/de/prod.tfvars` to `workspace-level/de/`. Change `name_prefix` to `dbxp`,
the groups to `dbxp-*`, and the subnets to new free ranges (e.g. 10.10.96.0/20 + 10.10.112.0/20). Then PR → merge →
run **3-promote-prod** with the run ID from the deploy summary.
