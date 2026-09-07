variable "account_id" {
  description = "AWS account this root deploys into (the management account)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "prod_account_id" {
  description = "AWS account ID of the prod workload account."
  type        = string
  default     = "111122223333"
}

variable "github_org" {
  description = "GitHub organisation allowed to assume the CI role."
  type        = string
  default     = "acme"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI role."
  type        = string
  default     = "platform"
}
