output "workspace_url" {
  value = data.terraform_remote_state.workspace.outputs.workspace_url
}

output "uc_bucket" {
  value = module.unity_catalog.bucket
}

output "catalogs" {
  value = module.unity_catalog.catalogs
}

output "shared_with" {
  value = module.unity_catalog.shared_with
}

output "cluster_policy_ids" {
  value = module.cluster_policies.policy_ids
}
