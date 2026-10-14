# Bootstrap stack: applied from your laptop, never from the pipeline.
# (The pipeline must not be able to edit the roles it runs under. Why?)

data "aws_caller_identity" "current" {}

# TODO(TP0.1): the Terraform state bucket
#   name:        bakehouse-tfstate-<account_id>
#   must have:   versioning, server-side encryption, public access block,
#                lifecycle { prevent_destroy = true }
#   resources:   aws_s3_bucket, aws_s3_bucket_versioning,
#                aws_s3_bucket_server_side_encryption_configuration,
#                aws_s3_bucket_public_access_block

# TODO(TP0.3): GitHub OIDC identity provider
#   url: https://token.actions.githubusercontent.com   audience: sts.amazonaws.com
#   resource: aws_iam_openid_connect_provider

# TODO(TP0.3): four IAM roles, one file each is fine (roles.tf)
#   bakehouse-gh-tf-plan        trusts: pull_request + main branch
#   bakehouse-gh-tf-apply       trusts: environment dev + environment prod
#   bakehouse-gh-artifacts      trusts: main branch
#   bakehouse-gh-image-factory  trusts: main branch
#   Each trust policy MUST pin both `aud` and `sub`. See docs/TP0-bootstrap.md.

# TODO(TP0.4): publish the role ARNs as GitHub repo variables (done with `gh variable set`, see outputs.tf)
