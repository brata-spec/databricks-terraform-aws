###############################################################################
# Shared by _template/workspace AND _template/config (CI checks they are
# identical). Values come from workspace-level/<team>/<env>.tfvars.
###############################################################################

# --- Identity of this deployment ------------------------------------------------
variable "team" {
  description = "Team key, e.g. de, ds, elections (lowercase, used in names)"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,14}$", var.team))
    error_message = "team: lowercase letters/digits, 2-15 chars."
  }
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "dbx"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# --- Network (existing VPC) -----------------------------------------------------
variable "network" {
  description = "Existing VPC + this workspace's subnets (see modules/workspace-network)"
  type = object({
    vpc_id            = string
    subnet_ids        = optional(list(string), [])
    new_subnets       = optional(map(string), {})
    route_table_ids   = optional(map(string), {})
    security_group_id = optional(string)
  })
}

variable "cross_account_role_arn" {
  description = "Existing cross-account role from CloudOps; null = create it"
  type        = string
  default     = null
}

# --- Access -----------------------------------------------------------------
variable "platform_admin_group" {
  type    = string
  default = "dbr-platform-admins"
}

variable "workspace_admin_groups" {
  description = "Account groups that get ADMIN on this workspace"
  type        = list(string)
  default     = []
}

variable "workspace_user_groups" {
  description = "Account groups that get USER on this workspace"
  type        = list(string)
  default     = []
}

# --- Unity Catalog + compute --------------------------------------------------------
variable "uc_owner_group" {
  description = "Owner of this team's catalogs/schemas/credential. null = platform_admin_group"
  type        = string
  default     = null
}

variable "kms_key_arn" {
  type    = string
  default = null
}

variable "catalogs" {
  description = "See modules/unity-catalog variable 'catalogs'"
  type        = any
  default     = {}
}

variable "cluster_policies" {
  description = "See modules/cluster-policies variable 'policies'"
  type        = any
  default     = {}
}

# --- Set by CI / scripts/tf.sh (TF_VAR_*) ------------------------------------------
variable "databricks_account_id" {
  type = string
}

variable "deployer_client_id" {
  type = string
}

variable "state_bucket" {
  description = "Terraform state bucket (to read account-level and other teams' state)"
  type        = string
}
