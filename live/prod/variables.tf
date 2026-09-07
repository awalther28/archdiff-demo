variable "account_id" {
  description = "AWS account this root deploys into (the prod workload account)."
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

variable "mgmt_account_id" {
  description = "AWS account ID of the management account."
  type        = string
  default     = "999988887777"
}

variable "audit_account_id" {
  description = "AWS account ID of the third-party auditor."
  type        = string
  default     = "555566667777"
}

variable "audit_external_id" {
  description = "External ID the auditor must present when assuming prod-app-admin."
  type        = string
  default     = "acme-audit-7f3a"
}
