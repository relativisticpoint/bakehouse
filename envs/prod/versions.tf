terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "bakehouse"
      Env       = "prod"
      ManagedBy = "terraform"
      Repo      = "bakehouse"
    }
  }
}
