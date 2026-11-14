# Elections - dev
# Plan/apply: scripts/tf.sh plan elections dev   (workspace, then config)
team        = "elections"
environment = "dev"
region      = "us-east-1"
name_prefix = "dbx" # resources: dbx-dev-elections-*

network = {
  vpc_id     = "vpc-<existing-vpc-id>"
  subnet_ids = ["subnet-<elections-dev-az-a>", "subnet-<elections-dev-az-b>"]
}

# cross_account_role_arn = "arn:aws:iam::<acct>:role/<name>" # only if CloudOps pre-creates it

workspace_admin_groups = ["dbr-elections-admins"]
workspace_user_groups  = ["dbr-elections-engineers", "dbr-elections-analysts"]

catalogs = {
  dev_elections = {
    comment = "Elections - dev"
    schemas = {
      bronze = { comment = "Raw ingested data" }
      silver = { comment = "Cleaned and conformed" }
      gold   = { comment = "Business-ready" }
    }
    grants = {
      "dbr-elections-engineers" = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_SCHEMA", "CREATE_TABLE", "CREATE_VOLUME", "READ_VOLUME", "WRITE_VOLUME", "CREATE_FUNCTION"]
      "dbr-elections-analysts"  = ["USE_CATALOG"]
    }
    schema_grants = {
      gold = { "dbr-elections-analysts" = ["USE_SCHEMA", "SELECT"] }
    }
  }
}

cluster_policies = {
  jobs = {
    description = "Job clusters for elections dev"
    node_types  = ["m6i.xlarge", "m6i.2xlarge", "r6i.xlarge"]
    max_workers = 8
    spot        = true
    groups      = ["dbr-elections-engineers"]
  }
}

tags = {
  CostCenter = "<cost-center>"
  Owner      = "elections-team"
}
