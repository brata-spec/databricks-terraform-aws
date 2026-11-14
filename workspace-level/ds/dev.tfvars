# Data Science - dev
# Plan/apply: scripts/tf.sh plan ds dev   (workspace, then config)
team        = "ds"
environment = "dev"
region      = "us-east-1"
name_prefix = "dbx" # resources: dbx-dev-ds-*

network = {
  vpc_id     = "vpc-<existing-vpc-id>"
  subnet_ids = ["subnet-<ds-dev-az-a>", "subnet-<ds-dev-az-b>"]
}

# cross_account_role_arn = "arn:aws:iam::<acct>:role/<name>" # only if CloudOps pre-creates it

workspace_admin_groups = ["dbr-ds-admins"]
workspace_user_groups  = ["dbr-ds-engineers", "dbr-ds-analysts"]

catalogs = {
  dev_ds = {
    comment = "Data Science - dev"
    schemas = {
      bronze = { comment = "Raw ingested data" }
      silver = { comment = "Cleaned and conformed" }
      gold   = { comment = "Business-ready" }
    }
    grants = {
      "dbr-ds-engineers" = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_SCHEMA", "CREATE_TABLE", "CREATE_VOLUME", "READ_VOLUME", "WRITE_VOLUME", "CREATE_FUNCTION"]
      "dbr-ds-analysts"  = ["USE_CATALOG"]
    }
    schema_grants = {
      gold = { "dbr-ds-analysts" = ["USE_SCHEMA", "SELECT"] }
    }
  }
}

cluster_policies = {
  jobs = {
    description = "Job clusters for ds dev"
    node_types  = ["m6i.xlarge", "m6i.2xlarge", "r6i.xlarge"]
    max_workers = 8
    spot        = true
    groups      = ["dbr-ds-engineers"]
  }
}

tags = {
  CostCenter = "<cost-center>"
  Owner      = "ds-team"
}
