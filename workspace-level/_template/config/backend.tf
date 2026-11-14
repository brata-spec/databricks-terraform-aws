terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.72.0, < 7.0.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.83.0, < 2.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.12.0"
    }
  }
  # key = workspace-config/<team>/<env>/terraform.tfstate  (scripts/tf.sh)
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = merge({
      Project     = "databricks-platform"
      Team        = var.team
      Environment = var.environment
      ManagedBy   = "terraform"
      Layer       = "config"
    }, var.tags)
  }
}

# Workspace-level provider: host from the workspace state, same SP credentials
provider "databricks" {
  host = data.terraform_remote_state.workspace.outputs.workspace_url
}
