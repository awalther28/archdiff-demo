# prod-app: application runtime role (child module).

module "workload" {
  source = "../../modules/workload-role"

  name        = "prod-app"
  data_bucket = local.data_bucket
}

# The app role needs the data key. This document references the key's ARN
# directly, which is unknown until apply -- so the ENTIRE rendered document
# (including the literal S3 statement) is deferred at plan time.
data "aws_iam_policy_document" "kms_use" {
  statement {
    sid    = "WriteAppData"
    effect = "Allow"

    actions = [
      "s3:PutObject",
    ]

    resources = [
      "${local.data_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "UseDataKey"
    effect = "Allow"

    actions = [
      "kms:GenerateDataKey*",
      "kms:Encrypt",
      "kms:Decrypt",
    ]

    resources = [
      aws_kms_key.main.arn,
    ]
  }
}

resource "aws_iam_policy" "kms_use" {
  name        = "prod-app-kms-use"
  description = "Use the application data key."

  policy = data.aws_iam_policy_document.kms_use.json
}

resource "aws_iam_role_policy_attachment" "app_kms_use" {
  role       = module.workload.role_name
  policy_arn = aws_iam_policy.kms_use.arn
}
