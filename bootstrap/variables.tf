variable "region" {
  description = "AWS region for everything in this project."
  type        = string
  default     = "eu-west-3"
}

variable "github_owner" {
  description = "GitHub user or org that owns the repository (used in OIDC trust conditions)."
  type        = string
  default     = "relativisticpoint"
}
  
variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "bakehouse"
}
