# Contract used by later TPs. Uncomment each output once the resource exists.
# Keep these names: docs and workflows refer to them.

# output "state_bucket" {
#   value = aws_s3_bucket.state.bucket
# }

# output "role_arns" {
#   value = {
#     tf_plan       = aws_iam_role.tf_plan.arn
#     tf_apply      = aws_iam_role.tf_apply.arn
#     artifacts     = aws_iam_role.artifacts.arn
#     image_factory = aws_iam_role.image_factory.arn
#   }
# }
