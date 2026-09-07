# prod-app-admin: privileged; reachable from the management account.

data "aws_iam_policy_document" "app_admin_assume_role" {
  # External auditor, gated on an external ID.
  statement {
    sid    = "ThirdPartyAudit"
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "AWS"
      identifiers = [
        local.audit_role_arn,
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.audit_external_id]
    }
  }

  # Deployments from the management account.
  statement {
    sid    = "ManagementDeploy"
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "AWS"
      identifiers = [
        local.mgmt_deploy_role_arn,
      ]
    }
  }
}

resource "aws_iam_role" "app_admin" {
  name                 = "prod-app-admin"
  description          = "Full control over the application's IAM, data and keys."
  max_session_duration = 3600

  assume_role_policy = data.aws_iam_policy_document.app_admin_assume_role.json
}

data "aws_iam_policy_document" "app_admin" {
  statement {
    sid    = "ManageKeys"
    effect = "Allow"

    actions = [
      "kms:*",
    ]

    resources = [
      "*",
    ]
  }

  statement {
    sid    = "FullDataAccess"
    effect = "Allow"

    actions = [
      "s3:*",
    ]

    resources = [
      "${local.data_bucket_arn}/*",
      local.data_bucket_arn,
    ]
  }

  statement {
    sid    = "ManageAppRoles"
    effect = "Allow"

    actions = [
      "iam:*",
    ]

    resources = [
      "arn:aws:iam::${var.account_id}:role/prod-*",
    ]
  }
}

resource "aws_iam_policy" "app_admin" {
  name        = "prod-app-admin"
  description = "Administrative permissions for the application."

  policy = data.aws_iam_policy_document.app_admin.json
}

resource "aws_iam_role_policy_attachment" "app_admin" {
  role       = aws_iam_role.app_admin.name
  policy_arn = aws_iam_policy.app_admin.arn
}
