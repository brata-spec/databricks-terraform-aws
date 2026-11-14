# Data Engineering - prod
# Plan/apply: scripts/tf.sh plan de prod   (workspace, then config)
team        = "de"
environment = "prod"
region      = "us-east-1"
name_prefix = "dbx" # resources: dbx-prod-de-*

network = {
  vpc_id     = "vpc-<existing-vpc-id>"
  subnet_ids = ["subnet-<de-prod-az-a>", "subnet-<de-prod-az-b>"]
}

# cross_account_role_arn = "arn:aws:iam::<acct>:role/<name>" # only if CloudOps pre-creates it

workspace_admin_groups = ["dbr-de-admins"]
workspace_user_groups  = ["dbr-de-engineers", "dbr-de-analysts"]

catalogs = {
  prod_de = {
    comment = "Data Engineering - prod"
    schemas = {
      bronze = { comment = "Raw ingested data" }
      silver = { comment = "Cleaned and conformed" }
      gold   = { comment = "Business-ready" }
    }
    # prod: people read; writes come from the job service principal (add it here)
    grants = {
      "dbr-de-engineers" = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "READ_VOLUME"]
      "dbr-de-analysts"  = ["USE_CATALOG"]
    }
    schema_grants = {
      gold = { "dbr-de-analysts" = ["USE_SCHEMA", "SELECT"] }
    }
    # Read-only share to the DS prod workspace: binding + USE CATALOG/USE SCHEMA/SELECT
    consumers = {
      ds = { groups = ["dbr-ds-engineers", "dbr-ds-analysts"], schemas = ["gold"] }
    }
  }
}

cluster_policies = {
  jobs = {
    description = "Job clusters for de prod"
    node_types  = ["m6i.xlarge", "m6i.2xlarge", "r6i.xlarge"]
    max_workers = 32
    spot        = true
    groups      = ["dbr-de-engineers"]
  }
}

tags = {
  CostCenter = "<cost-center>"
  Owner      = "de-team"
}
