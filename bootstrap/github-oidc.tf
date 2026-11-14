###############################################################################
# GitHub Actions -> AWS via OIDC (no stored AWS keys)
#
#   <prefix>-gha-plan         pull requests + plan_branches (main): read-only AWS + state read
#   <prefix>-gha-apply-<env>  only jobs running in GitHub environment <env>
#                             (protect prod with required reviewers in GitHub)
###############################################################################

locals {
  oidc_host = "token.actions.githubusercontent.com"
  repo      = "${var.github_org}/${var.github_repo}"

  # GitHub sends one of two "sub" formats:
  #   classic:   repo:<org>/<repo>:...
  #   immutable: repo:<org>@<org_id>/<repo>@<repo_id>:...   (use_immutable_subject = true)
  # Trust the immutable form when the IDs are given, plus the classic form unless disabled.
  sub_prefixes = compact([
    var.trust_classic_subject ? "repo:${local.repo}" : "",
    var.github_owner_id != null && var.github_repo_id != null
    ? "repo:${var.github_org}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}" : "",
  ])
  oidc_arn = (
    var.create_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
  envs = toset(var.environments)
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  # AWS validates GitHub tokens against its own trusted CA list and ignores these,
  # but older AWS provider versions still require the argument.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.oidc_host}"
}

# --- Trust policies ----------------------------------------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      # PR plans + the prod plan that runs on main before approval (read-only role)
      values = concat(
        [for p in local.sub_prefixes : "${p}:pull_request"],
        flatten([for p in local.sub_prefixes : [for b in var.plan_branches : "${p}:ref:refs/heads/${b}"]]),
      )
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  for_each = local.envs
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [for p in local.sub_prefixes : "${p}:environment:${each.key}"]
    }
  }
}

# --- Permissions -------------------------------------------------------------

# State: read for plan; read/write/lock for apply.
data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    sid       = "StateReadWriteLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

# Deploy: everything the workspace / UC stacks create, scoped to the prefix and region.
data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "Networking"
    actions   = ["ec2:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid = "IamRolesAndPoliciesWithPrefix"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:ListInstanceProfilesForRole",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListPolicyVersions",
      "iam:TagPolicy", "iam:UntagPolicy",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-*",
      "arn:aws:iam::${local.account_id}:policy/${var.name_prefix}-*",
    ]
  }

  statement {
    sid       = "IamPassPrefixedRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.name_prefix}-*"]
  }

  statement {
    sid     = "S3BucketsWithPrefix"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.name_prefix}-*",
      "arn:aws:s3:::${var.name_prefix}-*/*",
    ]
  }

  # The deploy role must never touch its own state bucket's config or delete state
  statement {
    sid    = "ProtectStateBucket"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
      "s3:PutBucketVersioning", "s3:PutLifecycleConfiguration",
      "s3:PutEncryptionConfiguration", "s3:PutBucketPublicAccessBlock",
      "s3:DeleteObjectVersion",
    ]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "Identity"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

# --- Roles -------------------------------------------------------------------

resource "aws_iam_role" "plan" {
  name                 = "${var.name_prefix}-gha-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_role" "apply" {
  for_each             = local.envs
  name                 = "${var.name_prefix}-gha-apply-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust[each.key].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "apply_state" {
  for_each = local.envs
  name     = "terraform-state"
  role     = aws_iam_role.apply[each.key].id
  policy   = data.aws_iam_policy_document.state_access.json
}

resource "aws_iam_role_policy" "apply_deploy" {
  for_each = local.envs
  name     = "databricks-deploy"
  role     = aws_iam_role.apply[each.key].id
  policy   = data.aws_iam_policy_document.deploy.json
}
