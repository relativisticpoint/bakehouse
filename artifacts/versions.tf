terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Same S3 bucket as every other stack, different key. Bucket name passed at init time
  # (-backend-config="bucket=..."), see envs/dev/backend.tf.
  backend "s3" {
    key          = "artifacts/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Project   = "bakehouse"
      ManagedBy = "terraform"
      Stack     = "artifacts"
    }
  }
}
