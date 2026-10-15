terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # !(TP0.2): once the bucket exists, add an s3 backend block here
  # (bucket, key = "bootstrap/terraform.tfstate", region, encrypt, use_lockfile = true)
  # then run: terraform init -migrate-state
  backend "s3" {
    bucket         = "bakehouse-tfstate-683803165943"
    key            = "bootstrap/terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    use_lockfile   = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "bakehouse"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}
