# Contract used by later TPs. Uncomment each output once the resource exists.
# Keep these names: docs and workflows refer to them.

output "state_bucket" {
  value = aws_s3_bucket.bakehouse-tfstate.bucket
}

output "role_arns" {
  value = {
    tf_plan       = aws_iam_role.bakehouse-gh-tf-plan.arn
    tf_apply      = aws_iam_role.bakehouse-gh-tf-apply.arn
    artifacts     = aws_iam_role.bakehouse-gh-artifacts.arn
    image_factory = aws_iam_role.bakehouse-gh-image-factory.arn
  }
}
