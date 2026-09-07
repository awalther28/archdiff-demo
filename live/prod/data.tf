# Data plane: the application bucket and its key.

resource "aws_kms_key" "main" {
  description         = "prod application data key"
  enable_key_rotation = true
}

resource "aws_s3_bucket" "data" {
  bucket = local.data_bucket
}
