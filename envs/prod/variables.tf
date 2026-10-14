variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-3"
}

variable "vpc_cidr" {
  description = "VPC CIDR for this environment."
  type        = string
}

variable "ami_id" {
  description = "Golden AMI id. null = look up the latest AMI tagged Channel=approved (dev only; prod must pin)."
  type        = string
  default     = null
}

variable "app_image_digest" {
  description = "Digest of the app image in bakehouse/app-releases, e.g. sha256:<64 hex>."
  type        = string

  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.app_image_digest))
    error_message = "app_image_digest must look like sha256:<64 hex chars>."
  }
}
