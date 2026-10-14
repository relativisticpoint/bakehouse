# Dev environment composition.
#
# TODO(TP1.2): call ../../modules/network with name = "bakehouse-dev" and var.vpc_cidr
# TODO(TP4.2): look up the approved AMI when var.ami_id is null:
#                data "aws_ami" with owners = ["self"], most_recent = true,
#                filters on tag:Project=bakehouse and tag:Channel=approved
#              call ../../modules/service with:
#                app_image           = "<acct>.dkr.ecr.eu-west-3.amazonaws.com/bakehouse/app-releases@${var.app_image_digest}"
#                ecr_repository_arns = candidates + releases (dev may test candidates)
