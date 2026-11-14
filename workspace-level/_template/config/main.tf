###############################################################################
# workspace-level/_template/config   (one state per team per env)
#   state key: workspace-config/<team>/<env>/terraform.tfstate
#
#   Runs AFTER the workspace root. Inside the team's workspace:
#   UC storage -> catalogs -> schemas -> grants -> cross-team read-only shares
#   cluster policies
###############################################################################

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "workspace" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "workspace/${var.team}/${var.environment}/terraform.tfstate"
    region = var.region
  }
}

# Workspaces of teams that consume this team's catalogs (read-only binding).
# Consumer = another team in the SAME environment; its workspace must exist.
locals {
  prefix         = "${var.name_prefix}-${var.environment}-${var.team}"
  consumer_teams = toset(distinct(flatten([for c in values(var.catalogs) : keys(try(c.consumers, {}))])))
}

data "terraform_remote_state" "consumer" {
  for_each = local.consumer_teams
  backend  = "s3"
  defaults = { workspace_id = 0 } # consumer workspace not created yet -> share waits
  config = {
    bucket = var.state_bucket
    key    = "workspace/${each.key}/${var.environment}/terraform.tfstate"
    region = var.region
  }
}

module "unity_catalog" {
  source = "../../../modules/unity-catalog"

  prefix                 = local.prefix
  team                   = var.team
  environment            = var.environment
  aws_account_id         = data.aws_caller_identity.current.account_id
  owner                  = coalesce(var.uc_owner_group, var.platform_admin_group)
  kms_key_arn            = var.kms_key_arn
  catalogs               = var.catalogs
  consumer_workspace_ids = { for t, s in data.terraform_remote_state.consumer : t => s.outputs.workspace_id }
}

module "cluster_policies" {
  source = "../../../modules/cluster-policies"

  prefix      = local.prefix
  team        = var.team
  environment = var.environment
  tags        = var.tags
  policies    = var.cluster_policies
}
