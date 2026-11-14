# Data Science - prod
# Plan/apply: scripts/tf.sh plan ds prod   (workspace, then config)
team        = "ds"
environment = "prod"
region      = "us-east-1"
name_prefix = "dbx" # resources: dbx-prod-ds-*

network = {
  vpc_id     = "vpc-<existing-vpc-id>"
  subnet_ids = ["subnet-<ds-prod-az-a>", "subnet-<ds-prod-az-b>"]
}

# cross_account_role_arn = "arn:aws:iam::<acct>:role/<name>" # only if CloudOps pre-creates it

workspace_admin_groups = ["dbr-ds-admins"]
workspace_user_groups  = ["dbr-ds-engineers", "dbr-ds-analysts"]

catalogs = {
  prod_ds = {
    comment = "Data Science - prod"
    schemas = {
      bronze = { comment = "Raw ingested data" }
      silver = { comment = "Cleaned and conformed" }
      gold   = { comment = "Business-ready" }
    }
    # prod: people read; writes come from the job service principal (add it here)
    grants = {
      "dbr-ds-engineers" = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "READ_VOLUME"]
      "dbr-ds-analysts"  = ["USE_CATALOG"]
    }
    schema_grants = {
      gold = { "dbr-ds-analysts" = ["USE_SCHEMA", "SELECT"] }
    }
  }
}

cluster_policies = {
  jobs = {
    description = "Job clusters for ds prod"
    node_types  = ["m6i.xlarge", "m6i.2xlarge", "r6i.xlarge"]
    max_workers = 32
    spot        = true
    groups      = ["dbr-ds-engineers"]
  }
}

tags = {
  CostCenter = "<cost-center>"
  Owner      = "ds-team"
}
