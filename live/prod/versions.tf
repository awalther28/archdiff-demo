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

  # Credentials profile. Profile "prod" is the prod workload account
  # (111122223333); see README "Accounts" and scripts/gen-plans.sh.
  profile = "prod"

  # Offline planning: no credential validation, no STS/IAM/IMDS calls.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}
