# Address changes from the module refactor. These are renames, not
# replacements: the underlying roles and policies are unchanged.

moved {
  from = module.app
  to   = module.workload
}

moved {
  from = aws_iam_role.deployer
  to   = module.deployer.aws_iam_role.this
}

moved {
  from = aws_iam_role_policy.deployer
  to   = module.deployer.aws_iam_role_policy.this
}
