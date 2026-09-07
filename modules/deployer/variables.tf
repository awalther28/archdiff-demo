variable "name" {
  description = "Name of the deployer role and its inline policy."
  type        = string
}

variable "trusted_role_arns" {
  description = "Role ARNs allowed to assume the deployer role."
  type        = list(string)
}

variable "function_arns" {
  description = "Lambda function ARNs (or patterns) the deployer may update."
  type        = list(string)
}

variable "passable_role_arns" {
  description = "Role ARNs the deployer may pass to Lambda."
  type        = list(string)
}
