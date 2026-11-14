output "bucket" {
  value = aws_s3_bucket.uc.bucket
}

output "iam_role_arn" {
  value = aws_iam_role.uc.arn
}

output "storage_credential" {
  value = databricks_storage_credential.this.name
}

output "external_location" {
  value = databricks_external_location.root.name
}

output "catalogs" {
  value = { for k, c in databricks_catalog.this : k => c.storage_root }
}

output "schemas" {
  value = keys(databricks_schema.this)
}

output "shared_with" {
  description = "catalog/team => consumer workspace id (read-only binding)"
  value       = { for k, b in databricks_workspace_binding.consumer : k => b.workspace_id }
}
