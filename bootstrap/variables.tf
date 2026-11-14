variable "aws_region" {
  description = "Region for the state bucket and the Databricks deployment, e.g. us-east-1"
  type        = string
}

variable "name_prefix" {
  description = <<-EOT
    Prefix for every AWS resource the pipeline creates, e.g. "dbx".
    The deploy roles can only manage IAM roles/policies and S3 buckets whose names
    start with "<name_prefix>-", so all later stacks must follow this convention.
  EOT
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.name_prefix))
    error_message = "name_prefix: lowercase letters, digits and hyphens, 2-16 chars, starting with a letter."
  }
}

variable "github_org" {
  description = "GitHub organisation or user that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "Repository name (without the org)"
  type        = string
}

variable "github_owner_id" {
  description = <<-EOT
    Numeric GitHub owner id, needed when the repo uses immutable OIDC subjects.
    Find it with: gh api repos/<org>/<repo>/actions/oidc/customization/sub
    (sub_claim_prefix "repo:<org>@<OWNER_ID>/<repo>@<REPO_ID>").
  EOT
  type        = string
  default     = null
}

variable "github_repo_id" {
  description = "Numeric GitHub repository id (see github_owner_id)."
  type        = string
  default     = null
}

variable "trust_classic_subject" {
  description = "Also trust the classic repo:<org>/<repo> subject. Set false to accept only the immutable form."
  type        = bool
  default     = true
}

variable "environments" {
  description = "Deployment environments. Each gets its own apply role, bound to the GitHub environment of the same name."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if this AWS account already has one (only one is allowed per account)."
  type        = bool
  default     = true
}

variable "state_bucket_name" {
  description = "Override the state bucket name. Default: <name_prefix>-tfstate-<account_id>-<region>"
  type        = string
  default     = null
}
