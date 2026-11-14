###############################################################################
# workspace-level/_template/workspace   (one state per team per env)
#   state key: workspace/<team>/<env>/terraform.tfstate
#
#   existing VPC + subnets -> SG -> cross-account role -> root bucket
#   -> workspace -> metastore assignment -> workspace permissions
###############################################################################

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "account" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "account-level/terraform.tfstate"
    region = var.region
  }
}

locals {
  prefix       = "${var.name_prefix}-${var.environment}-${var.team}" # dbx-dev-de
  metastore_id = data.terraform_remote_state.account.outputs.metastore_id
}

module "network" {
  source = "../../../modules/workspace-network"

  name              = local.prefix
  vpc_id            = var.network.vpc_id
  subnet_ids        = var.network.subnet_ids
  new_subnets       = var.network.new_subnets
  route_table_ids   = var.network.route_table_ids
  security_group_id = var.network.security_group_id
}

module "workspace" {
  source    = "../../../modules/databricks-workspace"
  providers = { databricks.mws = databricks.mws }

  prefix                 = local.prefix
  region                 = var.region
  databricks_account_id  = var.databricks_account_id
  aws_account_id         = data.aws_caller_identity.current.account_id
  vpc_id                 = module.network.vpc_id
  subnet_ids             = module.network.subnet_ids
  security_group_id      = module.network.security_group_id
  cross_account_role_arn = var.cross_account_role_arn
}

resource "databricks_metastore_assignment" "this" {
  provider     = databricks.mws
  metastore_id = local.metastore_id
  workspace_id = module.workspace.workspace_id
}

# --- Workspace permissions (identity federation) --------------------------------

data "databricks_service_principal" "deployer" {
  provider       = databricks.mws
  application_id = var.deployer_client_id
}

data "databricks_group" "this" {
  provider     = databricks.mws
  for_each     = toset(distinct(concat([var.platform_admin_group], var.workspace_admin_groups, var.workspace_user_groups)))
  display_name = each.value
}

locals {
  admin_groups = toset(distinct(concat([var.platform_admin_group], var.workspace_admin_groups)))
  assignments = merge(
    { "sp:deployer" = { id = data.databricks_service_principal.deployer.id, perm = "ADMIN" } },
    { for g in local.admin_groups : "group:${g}" => { id = data.databricks_group.this[g].id, perm = "ADMIN" } },
    { for g in var.workspace_user_groups : "group:${g}" => { id = data.databricks_group.this[g].id, perm = "USER" } if !contains(local.admin_groups, g) },
  )
}

resource "databricks_mws_permission_assignment" "this" {
  provider     = databricks.mws
  for_each     = local.assignments
  workspace_id = module.workspace.workspace_id
  principal_id = each.value.id
  permissions  = [each.value.perm]
  depends_on   = [databricks_metastore_assignment.this]
}
