# Build artifacts.

locals {
  artifacts_bucket     = "acme-build-artifacts"
  artifacts_bucket_arn = "arn:aws:s3:::${local.artifacts_bucket}"
}

resource "aws_s3_bucket" "artifacts" {
  bucket = local.artifacts_bucket
}
