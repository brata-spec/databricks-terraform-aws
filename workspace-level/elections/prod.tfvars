# Elections - prod
# Plan/apply: scripts/tf.sh plan elections prod   (workspace, then config)
team        = "elections"
environment = "prod"
region      = "us-east-1"
name_prefix = "dbx" # resources: dbx-prod-elections-*

network = {
  vpc_id     = "vpc-<existing-vpc-id>"
  subnet_ids = ["subnet-<elections-prod-az-a>", "subnet-<elections-prod-az-b>"]
}

# cross_account_role_arn = "arn:aws:iam::<acct>:role/<name>" # only if CloudOps pre-creates it

workspace_admin_groups = ["dbr-elections-admins"]
workspace_user_groups  = ["dbr-elections-engineers", "dbr-elections-analysts"]

catalogs = {
  prod_elections = {
    comment = "Elections - prod"
    schemas = {
      bronze = { comment = "Raw ingested data" }
      silver = { comment = "Cleaned and conformed" }
      gold   = { comment = "Business-ready" }
    }
    # prod: people read; writes come from the job service principal (add it here)
    grants = {
      "dbr-elections-engineers" = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "READ_VOLUME"]
      "dbr-elections-analysts"  = ["USE_CATALOG"]
    }
    schema_grants = {
      gold = { "dbr-elections-analysts" = ["USE_SCHEMA", "SELECT"] }
    }
  }
}

cluster_policies = {
  jobs = {
    description = "Job clusters for elections prod"
    node_types  = ["m6i.xlarge", "m6i.2xlarge", "r6i.xlarge"]
    max_workers = 32
    spot        = true
    groups      = ["dbr-elections-engineers"]
  }
}

tags = {
  CostCenter = "<cost-center>"
  Owner      = "elections-team"
}
