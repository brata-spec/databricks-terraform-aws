terraform {
  required_version = ">= 1.11.0" # S3 native state locking (use_lockfile)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.72.0"
    }
  }

  # Step 1: apply with local state (the bucket doesn't exist yet).
  backend "s3" {
  bucket       = "dbxp-tfstate-473640421776-us-east-1"
  key          = "<stack>/<env>/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true
}
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
