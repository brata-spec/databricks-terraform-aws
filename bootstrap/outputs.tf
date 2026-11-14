output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "aws_account_id" {
  value = local.account_id
}

output "plan_role_arn" {
  description = "GitHub repo variable AWS_PLAN_ROLE_ARN"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arns" {
  description = "GitHub environment variable AWS_APPLY_ROLE_ARN, one per environment"
  value       = { for env, r in aws_iam_role.apply : env => r.arn }
}

output "backend_snippet" {
  description = "Backend block for every later stack (change key per stack/env)"
  value       = <<-EOT
    backend "s3" {
      bucket       = "${aws_s3_bucket.state.bucket}"
      key          = "<stack>/<env>/terraform.tfstate"
      region       = "${var.aws_region}"
      encrypt      = true
      use_lockfile = true
    }
  EOT
}

output "trusted_github_subjects" {
  description = "OIDC subject prefixes the CI roles accept"
  value       = local.sub_prefixes
}
