# TODO(TP1.2): configure the S3 backend for this environment.
#   key          = "envs/dev/terraform.tfstate"
#   region       = "eu-west-3"
#   encrypt      = true
#   use_lockfile = true
#   bucket       = NOT hardcoded here: backend blocks can't use variables, so pass it at init time:
#                  terraform init -backend-config="bucket=bakehouse-tfstate-<account_id>"
#                  (the pipeline computes the account id from the OIDC role it assumed)
terraform {
  backend "s3" {}
}
