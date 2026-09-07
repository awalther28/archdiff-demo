# Prod workload account (111122223333)
#
# Holds the application data bucket and its KMS key, the privileged
# prod-app-admin role, the prod-deployer role (which can pass the app role to
# Lambda), and the application runtime role from a child module.
#
# Convention: policy bodies reference literal ARNs assembled from variables,
# never resource attributes, so that every document renders at plan time.
# The one deliberate exception is data.aws_iam_policy_document.kms_use below.

locals {
  data_bucket = "acme-prod-app-data"

  # Roles managed in this root.
  app_role_arn = "arn:aws:iam::${var.account_id}:role/prod-app"

  # Cross-account principals.
  mgmt_deploy_role_arn = "arn:aws:iam::${var.mgmt_account_id}:role/mgmt-deploy"
  audit_role_arn       = "arn:aws:iam::${var.audit_account_id}:role/third-party-audit"
}

# ---------------------------------------------------------------------------
# Data plane
# ---------------------------------------------------------------------------

resource "aws_kms_key" "main" {
  description         = "prod application data key"
  enable_key_rotation = true
}

resource "aws_s3_bucket" "data" {
  bucket = local.data_bucket
}

# ---------------------------------------------------------------------------
# prod-app-admin: privileged; reachable from the management account
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "app_admin_trust" {
  statement {
    sid     = "ManagementDeploy"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.mgmt_deploy_role_arn]
    }
  }

  statement {
    sid     = "ThirdPartyAudit"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.audit_role_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.audit_external_id]
    }
  }
}

resource "aws_iam_role" "app_admin" {
  name                 = "prod-app-admin"
  description          = "Full control over the application's IAM, data and keys."
  assume_role_policy   = data.aws_iam_policy_document.app_admin_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "app_admin" {
  statement {
    sid       = "ManageAppRoles"
    effect    = "Allow"
    actions   = ["iam:*"]
    resources = ["arn:aws:iam::${var.account_id}:role/prod-*"]
  }

  statement {
    sid     = "FullDataAccess"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${local.data_bucket}",
      "arn:aws:s3:::${local.data_bucket}/*",
    ]
  }

  statement {
    sid       = "ManageKeys"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app_admin" {
  name        = "prod-app-admin"
  description = "Administrative permissions for the application."
  policy      = data.aws_iam_policy_document.app_admin.json
}

resource "aws_iam_role_policy_attachment" "app_admin" {
  role       = aws_iam_role.app_admin.name
  policy_arn = aws_iam_policy.app_admin.arn
}

# ---------------------------------------------------------------------------
# prod-deployer: rolls out Lambda code; holds iam:PassRole for the app role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deployer_trust" {
  statement {
    sid     = "ManagementDeploy"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.mgmt_deploy_role_arn]
    }
  }
}

resource "aws_iam_role" "deployer" {
  name                 = "prod-deployer"
  description          = "Deploys application code; cannot change IAM."
  assume_role_policy   = data.aws_iam_policy_document.deployer_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deployer" {
  statement {
    sid    = "DeployFunctions"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
    ]
    resources = ["arn:aws:lambda:${var.region}:${var.account_id}:function:app-*"]
  }

  statement {
    sid       = "PassAppRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.app_role_arn]
  }
}

resource "aws_iam_role_policy" "deployer" {
  name   = "prod-deployer"
  role   = aws_iam_role.deployer.name
  policy = data.aws_iam_policy_document.deployer.json
}

# ---------------------------------------------------------------------------
# prod-app: application runtime role (child module)
# ---------------------------------------------------------------------------

module "app" {
  source = "../../modules/app-role"

  name        = "prod-app"
  data_bucket = local.data_bucket
}

# The app role needs the data key. This document references the key's ARN
# directly, which is unknown until apply -- so the ENTIRE rendered document
# (including the literal S3 statement) is deferred at plan time.
data "aws_iam_policy_document" "kms_use" {
  statement {
    sid    = "UseDataKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
    ]
    resources = [aws_kms_key.main.arn]
  }

  statement {
    sid       = "WriteAppData"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.data_bucket}/*"]
  }
}

resource "aws_iam_policy" "kms_use" {
  name        = "prod-app-kms-use"
  description = "Use the application data key."
  policy      = data.aws_iam_policy_document.kms_use.json
}

resource "aws_iam_role_policy_attachment" "app_kms_use" {
  role       = module.app.role_name
  policy_arn = aws_iam_policy.kms_use.arn
}
