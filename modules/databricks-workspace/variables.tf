variable "prefix" {
  description = "Resource prefix, e.g. dbx-dev. Also the workspace name."
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "databricks_account_id" {
  description = "Databricks account id (UUID)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account id the workspace is deployed into"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private workspace subnets, at least 2 AZs"
  type        = list(string)
  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least two subnets in different AZs are required."
  }
}

variable "security_group_id" {
  type = string
}

variable "cross_account_role_arn" {
  description = <<-EOT
    Existing cross-account role created by CloudOps. null = create it here.
    To have CloudOps create it, give them the trust and permission JSON from
    the databricks_aws_assume_role_policy / databricks_aws_crossaccount_policy
    data sources (see the 'cross_account_policy_json' outputs).
  EOT
  type        = string
  default     = null
}
