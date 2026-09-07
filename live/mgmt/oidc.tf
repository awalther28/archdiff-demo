# GitHub Actions OIDC entry point and the low-trust CI role.
#
# Policy bodies are assembled from variables and literals only so that every
# document renders at plan time.

locals {
  oidc_provider_arn = "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
  gha_role_arn      = "arn:aws:iam::${var.account_id}:role/gha"
  github_subject    = "repo:${var.github_org}/${var.github_repo}:*"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
  ]
}

data "aws_iam_policy_document" "gha_assume_role" {
  statement {
    sid    = "GitHubActionsOIDC"
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    principals {
      type = "Federated"
      identifiers = [
        local.oidc_provider_arn,
      ]
    }

    # Restrict to this repository first, then pin the audience.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_subject]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gha" {
  name                 = "gha"
  description          = "Low-trust CI role assumed by GitHub Actions via OIDC."
  max_session_duration = 3600

  assume_role_policy = data.aws_iam_policy_document.gha_assume_role.json
}

data "aws_iam_policy_document" "gha_artifacts" {
  statement {
    sid    = "ListBuildArtifacts"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      local.artifacts_bucket_arn,
    ]
  }

  statement {
    sid    = "ReadBuildArtifacts"
    effect = "Allow"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${local.artifacts_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "gha_artifacts" {
  name        = "gha-artifacts-read"
  description = "Read access to the build-artifact bucket for CI."

  policy = data.aws_iam_policy_document.gha_artifacts.json
}

resource "aws_iam_role_policy_attachment" "gha_artifacts" {
  role       = aws_iam_role.gha.name
  policy_arn = aws_iam_policy.gha_artifacts.arn
}
