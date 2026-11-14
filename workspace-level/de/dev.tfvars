# Data Engineering - dev   (AWS 473640421776, us-east-1) -> workspace dbxp-dev-de
team        = "de"
environment = "dev"
region      = "us-east-1"
name_prefix = "dbxp" # must match bootstrap name_prefix (the CI roles may only touch dbxp-*)

# Existing VPC only. Subnets + security group are NEW.
#   VPC 10.10.0.0/16 already uses 10.10.0.0/19, 10.10.32.0/19 (old workspace) and 10.10.248.0/24 (NAT)
network = {
  vpc_id = "vpc-03950e5934415cd3c"

  new_subnets = {
    "us-east-1a" = "10.10.64.0/20"
    "us-east-1b" = "10.10.80.0/20"
  }
  # Existing private route tables (route to the NAT + S3 gateway endpoint), one per AZ
  route_table_ids = {
    "us-east-1a" = "rtb-<private-us-east-1a>"
    "us-east-1b" = "rtb-<private-us-east-1b>"
  }

  # security_group_id not set -> a new SG "dbxp-dev-de-workspace" with the Databricks rules.
  # The VPC's STS/Kinesis endpoints only accept this SG -> open 443 from the new SG:
  endpoint_security_group_ids = ["sg-0d0c3683a000e944e"]
}

platform_admin_group   = "dbxp-platform-admins"
workspace_admin_groups = ["dbxp-de-admins"]
workspace_user_groups  = ["dbxp-de-engineers", "dbxp-de-analysts"]

catalogs = {
  dbxp_dev_de = {
    comment = "Data Engineering - dev (dbxp)"
    schemas = {
      bronze = { comment = "Raw ingested data" }
      silver = { comment = "Cleaned and conformed" }
      gold   = { comment = "Business-ready" }
    }
    grants = {
      "dbxp-de-engineers" = ["USE_CATALOG", "USE_SCHEMA", "SELECT", "MODIFY", "CREATE_SCHEMA", "CREATE_TABLE", "CREATE_VOLUME", "READ_VOLUME", "WRITE_VOLUME", "CREATE_FUNCTION"]
      "dbxp-de-analysts"  = ["USE_CATALOG"]
    }
    schema_grants = {
      gold = { "dbxp-de-analysts" = ["USE_SCHEMA", "SELECT"] }
    }
  }
}

cluster_policies = {
  jobs = {
    description = "Job clusters for de dev"
    node_types  = ["m6i.xlarge", "m6i.2xlarge", "r6i.xlarge"]
    max_workers = 4
    spot        = true
    groups      = ["dbxp-de-engineers"]
  }
}

tags = {
  Owner = "de-team"
}
