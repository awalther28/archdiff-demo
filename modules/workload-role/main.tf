# Runtime role for the application's Lambda functions.
#
# Every policy body here is built from variables and literals only, so the
# rendered JSON is known at plan time.

locals {
  data_bucket_arn = "arn:aws:s3:::${var.data_bucket}"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid    = "LambdaService"
    effect = "Allow"

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role" "this" {
  name        = var.name
  description = "Runtime role for the ${var.name} Lambda functions."

  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "data_read" {
  statement {
    sid    = "ListAppData"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      local.data_bucket_arn,
    ]
  }

  statement {
    sid    = "ReadAppData"
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${local.data_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "data_read" {
  name        = "${var.name}-data-read"
  description = "Read-only access to the application data bucket."

  policy = data.aws_iam_policy_document.data_read.json
}

resource "aws_iam_role_policy_attachment" "data_read" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.data_read.arn
}
