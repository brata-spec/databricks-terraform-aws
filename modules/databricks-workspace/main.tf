###############################################################################
# workspace: Databricks workspace on a customer-managed VPC
#
#   - cross-account IAM role ("restricted" policy, scoped to this VPC + SG),
#     or an existing role ARN supplied by CloudOps
#   - workspace root S3 bucket + Databricks bucket policy
#   - mws credentials, storage configuration, network, workspace
###############################################################################

# --- Cross-account role ----------------------------------------------------------

data "databricks_aws_assume_role_policy" "this" {
  provider    = databricks.mws
  external_id = var.databricks_account_id
}

data "databricks_aws_crossaccount_policy" "this" {
  provider          = databricks.mws
  policy_type       = "restricted"
  aws_account_id    = var.aws_account_id
  region            = var.region
  vpc_id            = var.vpc_id
  security_group_id = var.security_group_id
}

locals {
  create_role = var.cross_account_role_arn == null
  role_arn    = local.create_role ? aws_iam_role.cross_account[0].arn : var.cross_account_role_arn
}

resource "aws_iam_role" "cross_account" {
  count              = local.create_role ? 1 : 0
  name               = "${var.prefix}-crossaccount"
  description        = "Databricks control plane access for workspace ${var.prefix}"
  assume_role_policy = data.databricks_aws_assume_role_policy.this.json
}

resource "aws_iam_role_policy" "cross_account" {
  count  = local.create_role ? 1 : 0
  name   = "databricks-crossaccount"
  role   = aws_iam_role.cross_account[0].id
  policy = data.databricks_aws_crossaccount_policy.this.json
}

# IAM is eventually consistent; Databricks validates the role on create.
resource "time_sleep" "iam_propagation" {
  depends_on      = [aws_iam_role_policy.cross_account]
  create_duration = "30s"
}

resource "databricks_mws_credentials" "this" {
  provider         = databricks.mws
  credentials_name = "${var.prefix}-credentials"
  role_arn         = local.role_arn
  depends_on       = [time_sleep.iam_propagation]
}

# --- Root bucket (workspace system data: DBFS root, logs, notebooks results) -----

resource "aws_s3_bucket" "root" {
  bucket        = "${var.prefix}-root-${var.aws_account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "root" {
  bucket                  = aws_s3_bucket.root.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "root" {
  bucket = aws_s3_bucket.root.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root" {
  bucket = aws_s3_bucket.root.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

data "databricks_aws_bucket_policy" "root" {
  provider = databricks.mws
  bucket   = aws_s3_bucket.root.bucket
}

resource "aws_s3_bucket_policy" "root" {
  bucket     = aws_s3_bucket.root.id
  policy     = data.databricks_aws_bucket_policy.root.json
  depends_on = [aws_s3_bucket_public_access_block.root]
}

resource "databricks_mws_storage_configurations" "this" {
  provider                   = databricks.mws
  account_id                 = var.databricks_account_id
  storage_configuration_name = "${var.prefix}-storage"
  bucket_name                = aws_s3_bucket.root.bucket
  depends_on                 = [aws_s3_bucket_policy.root]
}

# --- Network + workspace ----------------------------------------------------------

resource "databricks_mws_networks" "this" {
  provider           = databricks.mws
  account_id         = var.databricks_account_id
  network_name       = "${var.prefix}-network"
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]
}

resource "databricks_mws_workspaces" "this" {
  provider       = databricks.mws
  account_id     = var.databricks_account_id
  workspace_name = var.prefix
  aws_region     = var.region

  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = databricks_mws_networks.this.network_id

  timeouts {
    create = "30m"
  }
}
