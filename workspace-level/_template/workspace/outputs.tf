output "workspace_id" {
  value = module.workspace.workspace_id
}

output "workspace_url" {
  value = module.workspace.workspace_url
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "availability_zones" {
  value = module.network.availability_zones
}

output "security_group_id" {
  value = module.network.security_group_id
}

output "cross_account_role_arn" {
  value = module.workspace.cross_account_role_arn
}

output "root_bucket" {
  value = module.workspace.root_bucket
}
