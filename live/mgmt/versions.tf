terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Fake inline credentials. Nothing here is ever applied and the plan never
  # talks to AWS. Account identity is NOT declared here: it comes from the
  # required var.account_id (999988887777, the management account), which is visible in
  # the plan JSON as variables.account_id.value. A credentials profile is only
  # a name that resolves through ~/.aws/config, and allowed_account_ids /
  # assume_role {} both fail offline; see README "Accounts".
  access_key = "fake"
  secret_key = "fake"

  # Offline planning: no credential validation, no STS/IAM/IMDS calls.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}
