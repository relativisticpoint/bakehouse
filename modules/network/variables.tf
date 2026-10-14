variable "name" {
  description = "Name prefix for resources (e.g. bakehouse-dev)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones / public subnets to create."
  type        = number
  default     = 2
}
