# prod-deployer: rolls out Lambda code; holds iam:PassRole for the app role.

module "deployer" {
  source = "../../modules/deployer"

  name = "prod-deployer"

  trusted_role_arns = [
    local.mgmt_deploy_role_arn,
  ]

  function_arns = [
    "arn:aws:lambda:${var.region}:${var.account_id}:function:app-*",
  ]

  passable_role_arns = [
    local.app_role_arn,
  ]
}
