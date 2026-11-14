terraform {
  required_version = ">= 1.11.0"
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.83.0, < 2.0.0"
    }
  }

  # Partial backend: bucket / key / region come from scripts/tf.sh (-backend-config)
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

# Auth from env: DATABRICKS_CLIENT_ID / DATABRICKS_CLIENT_SECRET (+ DATABRICKS_AUTH_TYPE)
provider "databricks" {
  alias      = "mws"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
}
