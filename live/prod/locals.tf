locals {
  data_bucket     = "acme-prod-app-data"
  data_bucket_arn = "arn:aws:s3:::${local.data_bucket}"

  # Roles managed in this root.
  app_role_arn       = "arn:aws:iam::${var.account_id}:role/prod-app"
  app_admin_role_arn = "arn:aws:iam::${var.account_id}:role/prod-app-admin"

  # Cross-account principals.
  mgmt_deploy_role_arn = "arn:aws:iam::${var.mgmt_account_id}:role/mgmt-deploy"
  audit_role_arn       = "arn:aws:iam::${var.audit_account_id}:role/third-party-audit"
}
