terraform {
  required_version = ">= 1.11.0" # S3 native state locking (use_lockfile)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.72.0"
    }
  }

  # Step 1: apply with local state.
  # Step 2: uncomment, fill in, then `terraform init -migrate-state`.
  # backend "s3" {
  #   bucket       = "<state_bucket output>"
  #   key          = "bootstrap/terraform.tfstate"
  #   region       = "<aws_region>"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      managed-by = "terraform"
      stack      = "bootstrap"
      platform   = var.name_prefix
    }
  }
}
