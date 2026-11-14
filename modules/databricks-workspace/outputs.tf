output "workspace_id" {
  value = databricks_mws_workspaces.this.workspace_id
}

output "workspace_url" {
  value = databricks_mws_workspaces.this.workspace_url
}

output "cross_account_role_arn" {
  value = local.role_arn
}

output "cross_account_trust_json" {
  description = "Trust policy for the cross-account role (hand to CloudOps if they create the role)"
  value       = data.databricks_aws_assume_role_policy.this.json
}

output "cross_account_policy_json" {
  description = "Permission policy for the cross-account role (restricted to this VPC, SG and region)"
  value       = data.databricks_aws_crossaccount_policy.this.json
}

output "network_id" {
  value = databricks_mws_networks.this.network_id
}

output "root_bucket" {
  value = aws_s3_bucket.root.bucket
}
