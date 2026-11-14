###############################################################################
# unity-catalog: one team's Unity Catalog footprint in one environment
# (workspace provider of the team's workspace)
#
#   S3 bucket <prefix>-uc-<account>  +  IAM role <prefix>-uc-access
#   storage credential + external location     (bound to this workspace only)
#   catalogs (ISOLATED)  -> schemas  -> grants
#   consumers: read-only binding of a catalog to another team's workspace,
#              plus USE CATALOG / USE SCHEMA / SELECT for that team's groups
#
# Grants are non-authoritative (databricks_grant): owners may still add
# table-level grants in the UI without Terraform removing them.
###############################################################################

locals {
  role_name = "${var.prefix}-uc-access"
  role_arn  = "arn:aws:iam::${var.aws_account_id}:role/${local.role_name}"
  bucket    = "${var.prefix}-uc-${var.aws_account_id}"
}

# --- Bucket ----------------------------------------------------------------------

resource "aws_s3_bucket" "uc" {
  bucket        = local.bucket
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "uc" {
  bucket                  = aws_s3_bucket.uc.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "uc" {
  bucket = aws_s3_bucket.uc.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uc" {
  bucket = aws_s3_bucket.uc.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# --- Storage credential + IAM role ----------------------------------------------
# Credential first (role ARN is a known string) so its external_id can go into
# the role's trust policy; validation is skipped until the role exists.

resource "databricks_storage_credential" "this" {
  name            = "${var.prefix}-uc-credential"
  comment         = "Unity Catalog access to s3://${local.bucket}"
  owner           = var.owner
  isolation_mode  = "ISOLATION_MODE_ISOLATED"
  skip_validation = true

  aws_iam_role {
    role_arn = local.role_arn
  }
}

data "databricks_aws_unity_catalog_assume_role_policy" "this" {
  aws_account_id = var.aws_account_id
  role_name      = local.role_name
  external_id    = databricks_storage_credential.this.aws_iam_role[0].external_id
}

data "databricks_aws_unity_catalog_policy" "this" {
  aws_account_id = var.aws_account_id
  bucket_name    = aws_s3_bucket.uc.bucket
  role_name      = local.role_name
  kms_name       = var.kms_key_arn
}

resource "aws_iam_role" "uc" {
  name               = local.role_name
  description        = "Unity Catalog storage access for ${var.prefix}"
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.this.json
}

resource "aws_iam_role_policy" "uc" {
  name   = "unity-catalog-access"
  role   = aws_iam_role.uc.id
  policy = data.databricks_aws_unity_catalog_policy.this.json
}

resource "time_sleep" "iam_propagation" {
  depends_on      = [aws_iam_role_policy.uc]
  create_duration = "30s"
}

resource "databricks_external_location" "root" {
  name            = "${var.prefix}-uc-root"
  url             = "s3://${local.bucket}"
  credential_name = databricks_storage_credential.this.name
  owner           = var.owner
  isolation_mode  = "ISOLATION_MODE_ISOLATED"
  comment         = "Root of ${var.prefix} Unity Catalog storage"
  depends_on      = [time_sleep.iam_propagation]
}

# --- Catalogs and schemas --------------------------------------------------------

resource "databricks_catalog" "this" {
  for_each       = var.catalogs
  name           = each.key
  comment        = each.value.comment
  owner          = coalesce(each.value.owner, var.owner)
  storage_root   = "s3://${local.bucket}/catalogs/${each.key}"
  isolation_mode = "ISOLATED"
  properties     = merge({ environment = var.environment, team = var.team }, each.value.properties)
  depends_on     = [databricks_external_location.root]
}

locals {
  schemas = merge([
    for cat, c in var.catalogs : {
      for sch, s in c.schemas : "${cat}.${sch}" => {
        catalog = cat
        name    = sch
        comment = s.comment
        owner   = coalesce(s.owner, c.owner, var.owner)
      }
    }
  ]...)
}

resource "databricks_schema" "this" {
  for_each      = local.schemas
  catalog_name  = databricks_catalog.this[each.value.catalog].name
  name          = each.value.name
  comment       = each.value.comment
  owner         = each.value.owner
  force_destroy = false # never drop a schema that still holds tables
}

# --- Cross-team consumers: read-only workspace binding ---------------------------

locals {
  bindings = merge([
    for cat, c in var.catalogs : {
      for team, cons in c.consumers : "${cat}/${team}" => {
        catalog      = cat
        workspace_id = lookup(var.consumer_workspace_ids, team, 0)
      }
    }
  ]...)
}

resource "databricks_workspace_binding" "consumer" {
  for_each       = { for k, v in local.bindings : k => v if v.workspace_id != 0 }
  securable_name = databricks_catalog.this[each.value.catalog].name
  securable_type = "catalog"
  workspace_id   = each.value.workspace_id
  binding_type   = "BINDING_TYPE_READ_ONLY"
  depends_on     = [terraform_data.checks]
}

# --- Grants (team grants + consumer grants, merged per principal) ---------------

locals {
  # catalog-level: explicit grants  ∪  USE_CATALOG for every consumer group
  catalog_grant_pairs = flatten([
    for cat, c in var.catalogs : concat(
      [for p, privs in c.grants : { catalog = cat, principal = p, privileges = privs }],
      flatten([for team, cons in c.consumers : [
        for g in cons.groups : { catalog = cat, principal = g, privileges = ["USE_CATALOG"] }
      ]]),
    )
  ])
  catalog_grants = {
    for k, v in { for x in local.catalog_grant_pairs : "${x.catalog}/${x.principal}" => x... } :
    k => { catalog = v[0].catalog, principal = v[0].principal, privileges = sort(distinct(flatten(v[*].privileges))) }
  }

  # schema-level: explicit schema_grants  ∪  USE_SCHEMA + SELECT on consumer schemas
  schema_grant_pairs = flatten([
    for cat, c in var.catalogs : concat(
      flatten([for sch, principals in c.schema_grants : [
        for p, privs in principals : { schema = "${cat}.${sch}", principal = p, privileges = privs }
      ]]),
      flatten([for team, cons in c.consumers : [
        for sch in cons.schemas : [
          for g in cons.groups : { schema = "${cat}.${sch}", principal = g, privileges = ["USE_SCHEMA", "SELECT"] }
        ]
      ]]),
    )
  ])
  schema_grants = {
    for k, v in { for x in local.schema_grant_pairs : "${x.schema}/${x.principal}" => x... } :
    k => { schema = v[0].schema, principal = v[0].principal, privileges = sort(distinct(flatten(v[*].privileges))) }
  }

  unknown_grant_schemas = flatten([
    for cat, c in var.catalogs : [for sch in keys(c.schema_grants) : "${cat}.${sch}" if !contains(keys(c.schemas), sch)]
  ])

  missing_consumer_ids = distinct(flatten([
    for cat, c in var.catalogs : [for team in keys(c.consumers) : team if !contains(keys(var.consumer_workspace_ids), team)]
  ]))

  unknown_consumer_schemas = flatten([
    for cat, c in var.catalogs : [
      for team, cons in c.consumers : [
        for sch in cons.schemas : "${cat}.${sch}" if !contains(keys(c.schemas), sch)
      ]
    ]
  ])
}

check "consumer_workspaces_exist" {
  assert {
    condition     = alltrue([for k, v in local.bindings : v.workspace_id != 0])
    error_message = "Read-only share pending for: ${join(", ", [for k, v in local.bindings : k if v.workspace_id == 0])}. The consumer team's workspace in this environment does not exist yet; re-run after it is applied."
  }
}

resource "databricks_grant" "catalog" {
  for_each   = local.catalog_grants
  catalog    = databricks_catalog.this[each.value.catalog].name
  principal  = each.value.principal
  privileges = each.value.privileges
}

resource "terraform_data" "checks" {
  input = keys(var.catalogs)
  lifecycle {
    precondition {
      condition     = length(local.unknown_consumer_schemas) == 0
      error_message = "consumers reference schemas not defined in the catalog: ${join(", ", local.unknown_consumer_schemas)}"
    }
    precondition {
      condition     = length(local.unknown_grant_schemas) == 0
      error_message = "schema_grants reference schemas not defined in the catalog: ${join(", ", local.unknown_grant_schemas)}"
    }
    precondition {
      condition     = length(local.missing_consumer_ids) == 0
      error_message = "no workspace id for consumer team(s): ${join(", ", local.missing_consumer_ids)}"
    }
  }
}

resource "databricks_grant" "schema" {
  for_each   = { for k, v in local.schema_grants : k => v if contains(keys(local.schemas), v.schema) }
  schema     = databricks_schema.this[each.value.schema].id
  principal  = each.value.principal
  privileges = each.value.privileges
  depends_on = [terraform_data.checks]
}
