variable "region" {
  type = string
}

variable "metastore" {
  description = "create = true makes a new metastore; false looks up an existing one by name"
  type = object({
    create = bool
    name   = string
  })
}

variable "platform_admin_group" {
  description = "Existing account group that owns the metastore and is admin of every workspace"
  type        = string
  default     = "dbr-platform-admins"
}

variable "manage_deployer_membership" {
  description = "Add the deployer service principal to platform_admin_group (needed to create catalogs)"
  type        = bool
  default     = true
}

variable "account_groups" {
  description = "Account groups to create for teams. Leave empty when groups come from the IdP via SCIM."
  type        = list(string)
  default     = []
}

variable "databricks_account_id" {
  description = "Set by CI: TF_VAR_databricks_account_id"
  type        = string
}

variable "deployer_client_id" {
  description = "Set by CI: TF_VAR_deployer_client_id"
  type        = string
}
