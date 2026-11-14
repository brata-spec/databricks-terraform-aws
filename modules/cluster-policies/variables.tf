variable "prefix" {
  description = "Name prefix, e.g. dbx-dev-de"
  type        = string
}

variable "team" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  description = "Extra custom tags fixed on every cluster (cost center, owner)"
  type        = map(string)
  default     = {}
}

variable "policies" {
  description = "policy name => settings"
  type = map(object({
    description                 = optional(string, "")
    cluster_type                = optional(string, "job") # job | all-purpose
    node_types                  = list(string)
    max_workers                 = number
    spot                        = optional(bool, true)
    max_autotermination_minutes = optional(number, 60) # all-purpose only
    groups                      = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for p in values(var.policies) : contains(["job", "all-purpose"], p.cluster_type) && length(p.node_types) > 0 && p.max_workers >= 1])
    error_message = "cluster_type must be job or all-purpose; node_types non-empty; max_workers >= 1."
  }
}
