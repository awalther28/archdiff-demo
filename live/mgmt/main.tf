# Management account (999988887777)
#
# Holds the GitHub OIDC entry point, the low-trust CI role, the mgmt-deploy
# role that fans out into workload accounts, and the build-artifact bucket.
#
# Convention: policy bodies reference literal ARNs assembled from variables,
# never resource attributes, so that every document renders at plan time.

locals {
  oidc_provider_arn = "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # Roles managed in this root.
  gha_role_arn         = "arn:aws:iam::${var.account_id}:role/gha"
  mgmt_deploy_role_arn = "arn:aws:iam::${var.account_id}:role/mgmt-deploy"

  # Human operators arrive through IAM Identity Center; that role is not
  # managed here.
  sso_operator_role_arn = "arn:aws:iam::${var.account_id}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_PlatformOperator_1a2b3c4d5e6f7a8b"

  artifacts_bucket = "acme-build-artifacts"

  # Roles in the prod workload account that mgmt-deploy may assume.
  prod_deployer_role_arn  = "arn:aws:iam::${var.prod_account_id}:role/prod-deployer"
  prod_app_admin_role_arn = "arn:aws:iam::${var.prod_account_id}:role/prod-app-admin"
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC entry point
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "gha_trust" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "gha" {
  name                 = "gha"
  description          = "Low-trust CI role assumed by GitHub Actions via OIDC."
  assume_role_policy   = data.aws_iam_policy_document.gha_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "gha_artifacts" {
  statement {
    sid       = "ReadBuildArtifacts"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.artifacts_bucket}/*"]
  }

  statement {
    sid       = "ListBuildArtifacts"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.artifacts_bucket}"]
  }
}

resource "aws_iam_policy" "gha_artifacts" {
  name        = "gha-artifacts-read"
  description = "Read access to the build-artifact bucket for CI."
  policy      = data.aws_iam_policy_document.gha_artifacts.json
}

resource "aws_iam_role_policy_attachment" "gha_artifacts" {
  role       = aws_iam_role.gha.name
  policy_arn = aws_iam_policy.gha_artifacts.arn
}

# ---------------------------------------------------------------------------
# mgmt-deploy: the role that fans out into workload accounts
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "mgmt_deploy_trust" {
  statement {
    sid     = "OperatorAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.sso_operator_role_arn, local.gha_role_arn]
    }
  }
}

resource "aws_iam_role" "mgmt_deploy" {
  name                 = "mgmt-deploy"
  description          = "Deployment role; hops into workload accounts."
  assume_role_policy   = data.aws_iam_policy_document.mgmt_deploy_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "mgmt_deploy" {
  statement {
    sid     = "AssumeWorkloadRoles"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    resources = [
      local.prod_deployer_role_arn,
      local.prod_app_admin_role_arn,
    ]
  }

  statement {
    sid    = "PublishBuildArtifacts"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["arn:aws:s3:::${local.artifacts_bucket}/*"]
  }
}

resource "aws_iam_policy" "mgmt_deploy" {
  name        = "mgmt-deploy"
  description = "Permissions for the mgmt-deploy role."
  policy      = data.aws_iam_policy_document.mgmt_deploy.json
}

resource "aws_iam_role_policy_attachment" "mgmt_deploy" {
  role       = aws_iam_role.mgmt_deploy.name
  policy_arn = aws_iam_policy.mgmt_deploy.arn
}

# ---------------------------------------------------------------------------
# Build artifacts
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "artifacts" {
  bucket = local.artifacts_bucket
}
