output "policy_ids" {
  value = { for k, p in databricks_cluster_policy.this : k => p.id }
}
