output "metastore_id" {
  description = "Read by every workspace (metastore assignment)"
  value       = local.metastore_id
}

output "metastore_name" {
  value = var.metastore.name
}

output "platform_admin_group" {
  value = var.platform_admin_group
}

output "account_groups" {
  value = keys(databricks_group.team)
}
