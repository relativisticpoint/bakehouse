# Bootstrap stack: applied from your laptop, never from the pipeline.
# (The pipeline must not be able to edit the roles it runs under. Why?)

data "aws_caller_identity" "current" {}

# ! (TP0.1): the Terraform state bucket
#   name:        bakehouse-tfstate-<account_id>
#   must have:   versioning, server-side encryption, public access block,
#                lifecycle { prevent_destroy = true }
#   resources:   aws_s3_bucket, aws_s3_bucket_versioning,
#                aws_s3_bucket_server_side_encryption_configuration,
#                aws_s3_bucket_public_access_block

resource "aws_s3_bucket" "bakehouse-tfstate" {
    bucket = format("bakehouse-tfstate-%s",data.aws_caller_identity.current.account_id)
    lifecycle {
        prevent_destroy = true
    }

}
resource "aws_s3_bucket_versioning" "bakehouse-tfstate" {
    bucket = aws_s3_bucket.bakehouse-tfstate.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bakehouse-tfstate" {
    bucket = aws_s3_bucket.bakehouse-tfstate.id
    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}
resource "aws_s3_bucket_public_access_block" "bakehouse-tfstate" {
    bucket = aws_s3_bucket.bakehouse-tfstate.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}



# !(TP0.3): GitHub OIDC identity provider
#   url: https://token.actions.githubusercontent.com   audience: sts.amazonaws.com
#   resource: aws_iam_openid_connect_provider
resource "aws_iam_openid_connect_provider" "default" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}


# !(TP0.3): four IAM roles, one file each is fine (roles.tf)
#   bakehouse-gh-tf-plan        trusts: pull_request + main branch
#   bakehouse-gh-tf-apply       trusts: environment dev + environment prod
#   bakehouse-gh-artifacts      trusts: main branch
#   bakehouse-gh-image-factory  trusts: main branch
#   Each trust policy MUST pin both `aud` and `sub`. See docs/TP0-bootstrap.md.
resource "aws_iam_role" "bakehouse-gh-tf-plan" {
    name = "bakehouse-gh-tf-plan"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Federated = aws_iam_openid_connect_provider.default.arn
                }
                Action = "sts:AssumeRoleWithWebIdentity"
                Condition = {
                    StringEquals = {
                        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
                        "token.actions.githubusercontent.com:sub" = [
                            "repo:${var.github_owner}/${var.github_repo}:pull_request",
                            "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"
                        ]
                    }
                }

            }
        ]
    })
}

resource "aws_iam_role" "bakehouse-gh-tf-apply"{
    name = "bakehouse-gh-tf-apply"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement =[
            {
                Effect = "Allow"
                Principal = {
                    Federated = aws_iam_openid_connect_provider.default.arn
                }
                Action = "sts:AssumeRoleWithWebIdentity"
                Condition ={
                    StringEquals = {
                        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
                        "token.actions.githubusercontent.com:sub" = [
                                "repo:${var.github_owner}/${var.github_repo}:environment:dev",
                                "repo:${var.github_owner}/${var.github_repo}:environment:prod"
                            ]
                    }
                }
            }
            
        ]
    })
}

resource "aws_iam_role" "bakehouse-gh-artifacts" {
    name = "bakehouse-gh-artifacts"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Federated = aws_iam_openid_connect_provider.default.arn
                }
                Action = "sts:AssumeRoleWithWebIdentity"
                Condition = {
                    StringEquals = {
                        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
                        "token.actions.githubusercontent.com:sub" ="repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"
                    }
                }

            }
        ]
    })
}

resource "aws_iam_role" "bakehouse-gh-image-factory" {
    name = "bakehouse-gh-image-factory"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Federated = aws_iam_openid_connect_provider.default.arn
                }
                Action = "sts:AssumeRoleWithWebIdentity"
                Condition = {
                    StringEquals = {
                        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
                        "token.actions.githubusercontent.com:sub" ="repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"
                    }
                }

            }
        ]
    })
}

# create the IAM policies for the roles, and attach them to the roles
# IAM role policy for the role bakehouse-gh-tf-plan: ReadOnlyAccess + S3 read access to the tfstate bucket
resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
    role = aws_iam_role.bakehouse-gh-tf-plan.id
    policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
resource "aws_iam_role_policy" "tf_plan_state" {
    name = "tf_plan_state"
    role = aws_iam_role.bakehouse-gh-tf-plan.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:ListBucket",
                ]
                Resource = [
                    "${aws_s3_bucket.bakehouse-tfstate.arn}/*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "s3:PutObject",
                    "s3:DeleteObject"
                ]
                Resource = [
                    aws_s3_bucket.bakehouse-tfstate.arn,
                    "${aws_s3_bucket.bakehouse-tfstate.arn}/*.tflock"
                ]
            }
        ]
    })
}
# IAM role policy for the role bakehouse-gh-tf-apply: S3 read/write access to the tfstate bucket
resource "aws_iam_role_policy_attachment" "tf_apply_poweruser" {
  role       = aws_iam_role.bakehouse-gh-tf-apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
resource "aws_iam_role_policy" "tf_apply_state" {
    name = "tf_apply_state"
    role = aws_iam_role.bakehouse-gh-tf-apply.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:ListBucket",
                    "s3:PutObject",
                    "s3:DeleteObject"
                ]
                Resource = [
                    aws_s3_bucket.bakehouse-tfstate.arn,
                    "${aws_s3_bucket.bakehouse-tfstate.arn}/*"
                ]
            }
        ]
    })
}
resource "aws_iam_role_policy" "tf_apply_iam" {
  name = "bakehouse-tf-apply-iam"
  role = aws_iam_role.bakehouse-gh-tf-apply.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
      ]
      Resource = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/bakehouse-dev-*",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/bakehouse-prod-*",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/bakehouse-dev-*",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/bakehouse-prod-*",
      ]
    }]
  })
}

# IAM role policy for the role bakehouse-gh-artifacts: ECR push/pull access to the bakehouse ECR repo + ECR:GetAuthorizationToken
resource "aws_iam_role_policy" "artifacts_ecr" {
    name = "artifacts_ecr"
    role = aws_iam_role.bakehouse-gh-artifacts.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "ecr:GetAuthorizationToken",
                ]
                Resource = "*"
            },
            {
                Effect = "Allow"
                Action = [
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:BatchGetImage",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:DescribeRepositories",
                    "ecr:GetRepositoryPolicy",
                    "ecr:ListImages",
                    "ecr:DescribeImages",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                    "ecr:PutImage",
                    "ecr:GetLifecyclePolicy",
                    "ecr:BatchDeleteImage",
                    "ecr:PutLifecyclePolicy",
                ]
                Resource = [
                    "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/bakehouse/*"
                ]
            }
        ]
    })
}

resource "aws_iam_role_policy" "image_factory_packer" {
  name = "bakehouse-image-factory-packer"
  role = aws_iam_role.bakehouse-gh-image-factory.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Packer amazon-ebs builder — all on * for now; TP3 tightens by tag
        Effect = "Allow"
        Action = [
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CopyImage",
          "ec2:CreateImage",
          "ec2:CreateKeyPair",
          "ec2:CreateSecurityGroup",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteKeyPair",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteSnapshot",
          "ec2:DeleteVolume",
          "ec2:DeregisterImage",
          "ec2:DescribeImageAttribute",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeRegions",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSnapshots",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVpcs",
          "ec2:DetachVolume",
          "ec2:EnableImageDeprecation",
          "ec2:GetPasswordData",
          "ec2:ModifyImageAttribute",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifySnapshotAttribute",
          "ec2:RegisterImage",
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
        ]
        Resource = "*"
      },
      {
        # SSM: AL2023 public parameter (no account in ARN — it's AWS-owned)
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.region}::parameter/aws/service/ami-amazon-linux-latest/*"
      }
    ]
  })
}


# !(TP0.4): publish the role ARNs as GitHub repo variables (done with `gh variable set`, see outputs.tf)
