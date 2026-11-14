# Data Engineering - dev
# Plan/apply: scripts/tf.sh plan de dev   (workspace, then config)
team        = "de"
environment = "dev"
region      = "us-east-1"
name_prefix = "dbx" # resources: dbx-dev-de-*

network = {
  vpc_id = "vpc-<existing-vpc-id>" # existing (CloudOps)

  # Option A (default): existing subnets CloudOps created for THIS workspace,
  # one per AZ, at least 2 AZs, not shared with any other workspace.
  subnet_ids = ["subnet-<de-dev-az-a>", "subnet-<de-dev-az-b>"]

  # Option B: let Terraform create them in free VPC space (comment out subnet_ids)
  # new_subnets     = { "us-east-1a" = "10.20.0.0/22", "us-east-1b" = "10.20.4.0/22" }
  # route_table_ids = { "us-east-1a" = "rtb-0private1a", "us-east-1b" = "rtb-0private1b" }

  # security_group_id = "sg-0..." # omit = create a dedicated SG with the Databricks rules
}

# cross_account_role_arn = "arn:aws:iam::<acct>:role/<name>" # only if CloudOps pre-creates it

workspace_admin_groups = ["dbr-de-admins"]
workspace_user_groups  = ["dbr-de-engineers", "dbr-de-analysts"]

catalogs = {
  dev_de = {
    comment = "Data Engineering - dev"
    schemas = {
      bronze = { comment = "Raw ingested data" }
      silver = { comment = "Cleaned and conformed" }
      gold   = { comment = "Business-ready" }
    }
    grants = {
      "dbr-de-engineers" = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_SCHEMA", "CREATE_TABLE", "CREATE_VOLUME", "READ_VOLUME", "WRITE_VOLUME", "CREATE_FUNCTION"]
      "dbr-de-analysts"  = ["USE_CATALOG"]
    }
    schema_grants = {
      gold = { "dbr-de-analysts" = ["USE_SCHEMA", "SELECT"] }
    }
  }
}

cluster_policies = {
  jobs = {
    description = "Job clusters for de dev"
    node_types  = ["m6i.xlarge", "m6i.2xlarge", "r6i.xlarge"]
    max_workers = 8
    spot        = true
    groups      = ["dbr-de-engineers"]
  }
}

tags = {
  CostCenter = "<cost-center>"
  Owner      = "de-team"
}
