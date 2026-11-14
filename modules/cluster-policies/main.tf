###############################################################################
# cluster-policies: job-cluster policies for one team workspace
#
# Each policy pins the settings a job cluster must use (AZ auto-placement,
# spot with on-demand driver, team/env tags, size limits) and grants CAN_USE
# to the listed groups. databricks_permissions is authoritative per policy,
# which is fine: each policy is owned by exactly this state.
###############################################################################

locals {
  definitions = {
    for name, p in var.policies : name => merge(
      {
        "cluster_type"                          = { type = "fixed", value = p.cluster_type }
        "spark_version"                         = { type = "unlimited", defaultValue = "auto:latest-lts" }
        "node_type_id"                          = { type = "allowlist", values = p.node_types, defaultValue = p.node_types[0] }
        "driver_node_type_id"                   = { type = "allowlist", values = p.node_types, defaultValue = p.node_types[0] }
        "autoscale.min_workers"                 = { type = "range", minValue = 1, maxValue = p.max_workers, defaultValue = 1 }
        "autoscale.max_workers"                 = { type = "range", minValue = 1, maxValue = p.max_workers, defaultValue = min(4, p.max_workers) }
        "num_workers"                           = { type = "range", minValue = 0, maxValue = p.max_workers }
        "aws_attributes.zone_id"                = { type = "fixed", value = "auto", hidden = true }
        "aws_attributes.availability"           = { type = "fixed", value = p.spot ? "SPOT_WITH_FALLBACK" : "ON_DEMAND", hidden = true }
        "aws_attributes.first_on_demand"        = { type = "fixed", value = 1, hidden = true }
        "aws_attributes.spot_bid_price_percent" = { type = "fixed", value = 100, hidden = true }
        "data_security_mode"                    = { type = "allowlist", values = ["SINGLE_USER", "USER_ISOLATION"], defaultValue = "SINGLE_USER" }
        "custom_tags.team"                      = { type = "fixed", value = var.team }
        "custom_tags.environment"               = { type = "fixed", value = var.environment }
      },
      {
        for k, v in {
          "autotermination_minutes" = { type = "range", minValue = 10, maxValue = p.max_autotermination_minutes, defaultValue = 30 }
        } : k => v if p.cluster_type == "all-purpose"
      },
      { for k, v in var.tags : "custom_tags.${k}" => { type = "fixed", value = v } },
    )
  }
}

resource "databricks_cluster_policy" "this" {
  for_each    = var.policies
  name        = "${var.prefix}-${each.key}"
  description = each.value.description
  definition  = jsonencode(local.definitions[each.key])
}

resource "databricks_permissions" "this" {
  for_each          = { for k, p in var.policies : k => p if length(p.groups) > 0 }
  cluster_policy_id = databricks_cluster_policy.this[each.key].id

  dynamic "access_control" {
    for_each = toset(each.value.groups)
    content {
      group_name       = access_control.value
      permission_level = "CAN_USE"
    }
  }
}
