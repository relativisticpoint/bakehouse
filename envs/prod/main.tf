# Prod environment composition. Same modules as dev, different inputs and stricter rules.
#
# TODO(TP1.2): call ../../modules/network with name = "bakehouse-prod" and var.vpc_cidr
# TODO(TP4.2): call ../../modules/service with:
#                ami_id              = var.ami_id   (PINNED: add a validation or precondition that it is not null)
#                app_image           = "<acct>.dkr.ecr.eu-west-3.amazonaws.com/bakehouse/app-releases@${var.app_image_digest}"
#                ecr_repository_arns = releases ONLY
