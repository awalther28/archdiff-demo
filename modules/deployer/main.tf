# A deployment role that can update application code but not IAM.
#
# Policy bodies are assembled from variables only so that every document
# renders at plan time.

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid    = "ManagementDeploy"
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "AWS"
      identifiers = var.trusted_role_arns
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  description          = "Deploys application code; cannot change IAM."
  max_session_duration = 3600

  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "PassAppRole"
    effect = "Allow"

    actions = [
      "iam:PassRole",
    ]

    resources = var.passable_role_arns
  }

  statement {
    sid    = "DeployFunctions"
    effect = "Allow"

    actions = [
      "lambda:UpdateFunctionConfiguration",
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
    ]

    resources = var.function_arns
  }
}

resource "aws_iam_role_policy" "this" {
  name = var.name
  role = aws_iam_role.this.name

  policy = data.aws_iam_policy_document.this.json
}
