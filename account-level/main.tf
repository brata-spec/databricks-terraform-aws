###############################################################################
# account-level  (Databricks account; ONE state for all teams and envs)
#   state key: account-level/terraform.tfstate
#
#   - Unity Catalog metastore for the region: created here, or an EXISTING one
#     looked up by name (one metastore per region per account)
#   - deployer service principal in the platform admin group (metastore rights)
#   - optional account groups for teams (skip if they come from SCIM)
###############################################################################

data "databricks_group" "platform_admins" {
  provider     = databricks.mws
  display_name = var.platform_admin_group
}

data "databricks_service_principal" "deployer" {
  provider       = databricks.mws
  application_id = var.deployer_client_id
}

resource "databricks_group_member" "deployer" {
  count     = var.manage_deployer_membership ? 1 : 0
  provider  = databricks.mws
  group_id  = data.databricks_group.platform_admins.id
  member_id = data.databricks_service_principal.deployer.id
}

# --- Metastore ---------------------------------------------------------------------

resource "databricks_metastore" "this" {
  count         = var.metastore.create ? 1 : 0
  provider      = databricks.mws
  name          = var.metastore.name
  region        = var.region
  owner         = var.platform_admin_group
  force_destroy = false
  depends_on    = [databricks_group_member.deployer]

  lifecycle {
    prevent_destroy = true
  }
}

data "databricks_metastore" "existing" {
  count    = var.metastore.create ? 0 : 1
  provider = databricks.mws
  name     = var.metastore.name
}

locals {
  metastore_id = var.metastore.create ? databricks_metastore.this[0].id : data.databricks_metastore.existing[0].metastore_id
}

# --- Team groups (only if not provisioned by SCIM) ----------------------------------

resource "databricks_group" "team" {
  for_each     = toset(var.account_groups)
  provider     = databricks.mws
  display_name = each.value
}
