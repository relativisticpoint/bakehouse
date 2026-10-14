variable "name" {
  description = "Name prefix (e.g. bakehouse-dev)."
  type        = string
}

variable "env" {
  description = "Environment name, passed to the app as APP_ENV."
  type        = string
}

variable "vpc_id" {
  description = "VPC to deploy into."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets for the ALB and the instances."
  type        = list(string)
}

variable "ami_id" {
  description = "Golden AMI to boot instances from."
  type        = string
}

variable "app_image" {
  description = "Full image reference pinned by digest: <acct>.dkr.ecr.<region>.amazonaws.com/bakehouse/app-releases@sha256:..."
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.app_image))
    error_message = "app_image must be pinned by digest (…@sha256:<64 hex chars>), never by a moving tag."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repositories the instance role may pull from (least privilege: prod gets releases only)."
  type        = list(string)
}

variable "instance_type" {
  description = "Graviton instance type."
  type        = string
  default     = "t4g.micro"
}

variable "desired_capacity" {
  description = "Number of instances."
  type        = number
  default     = 1
}
