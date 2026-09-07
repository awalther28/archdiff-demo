# mgmt-deploy: the role that fans out into workload accounts.

locals {
  mgmt_deploy_role_arn = "arn:aws:iam::${var.account_id}:role/mgmt-deploy"

  # Human operators arrive through IAM Identity Center; that role is not
  # managed here.
  sso_operator_role_arn = "arn:aws:iam::${var.account_id}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_PlatformOperator_1a2b3c4d5e6f7a8b"

  # Roles in the prod workload account that mgmt-deploy may assume.
  workload_role_arns = [
    "arn:aws:iam::${var.prod_account_id}:role/prod-app-admin",
    "arn:aws:iam::${var.prod_account_id}:role/prod-deployer",
  ]
}

data "aws_iam_policy_document" "mgmt_deploy_assume_role" {
  statement {
    sid    = "OperatorAssume"
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "AWS"
      identifiers = [
        local.sso_operator_role_arn,
      ]
    }
  }
}

resource "aws_iam_role" "mgmt_deploy" {
  name                 = "mgmt-deploy"
  description          = "Deployment role; hops into workload accounts."
  max_session_duration = 3600

  assume_role_policy = data.aws_iam_policy_document.mgmt_deploy_assume_role.json
}

data "aws_iam_policy_document" "mgmt_deploy" {
  statement {
    sid    = "PublishBuildArtifacts"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]

    resources = [
      "${local.artifacts_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "AssumeWorkloadRoles"
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    resources = local.workload_role_arns
  }
}

resource "aws_iam_policy" "mgmt_deploy" {
  name        = "mgmt-deploy"
  description = "Permissions for the mgmt-deploy role."

  policy = data.aws_iam_policy_document.mgmt_deploy.json
}

resource "aws_iam_role_policy_attachment" "mgmt_deploy" {
  role       = aws_iam_role.mgmt_deploy.name
  policy_arn = aws_iam_policy.mgmt_deploy.arn
}
