output "app_role_arn" {
  value = local.app_role_arn
}

output "app_admin_role_arn" {
  value = "arn:aws:iam::${var.account_id}:role/prod-app-admin"
}
