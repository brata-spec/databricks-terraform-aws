variable "prefix" {
  description = "Resource prefix, e.g. dbx-dev-de"
  type        = string
}

variable "team" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "owner" {
  description = "Default owner of credential, external location, catalogs and schemas. A group, never a person."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for the UC bucket. null = SSE-S3."
  type        = string
  default     = null
}

variable "catalogs" {
  description = "name => catalog definition (see the team tfvars for an example)"
  type = map(object({
    comment       = optional(string, "")
    owner         = optional(string)
    properties    = optional(map(string), {})
    schemas       = optional(map(object({ comment = optional(string, ""), owner = optional(string) })), {})
    grants        = optional(map(list(string)), {})      # principal => catalog privileges
    schema_grants = optional(map(map(list(string))), {}) # schema => principal => privileges
    consumers = optional(map(object({                    # other team => read-only access
      groups  = list(string)
      schemas = list(string)
    })), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.catalogs) : can(regex("^[a-z][a-z0-9_]*$", k))])
    error_message = "Catalog names: lowercase letters, digits and underscores, starting with a letter."
  }
}

variable "consumer_workspace_ids" {
  description = "team => workspace id, for every team named in a catalog's consumers (resolved by the root from state)"
  type        = map(number)
  default     = {}
}
