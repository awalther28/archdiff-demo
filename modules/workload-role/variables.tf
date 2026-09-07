variable "name" {
  description = "Name of the runtime role."
  type        = string
}

variable "data_bucket" {
  description = "Name of the S3 bucket the role may read from."
  type        = string
}
