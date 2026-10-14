# Network module: a VPC with public subnets only. No NAT Gateway (cost, ~$32/month idle).
#
# TODO(TP1.1): create
#   - aws_vpc (DNS support + hostnames enabled)
#   - public subnets, one per AZ (use data "aws_availability_zones" and cidrsubnet())
#   - internet gateway, a public route table with 0.0.0.0/0 -> IGW, associations
#   - tag everything with Name = "${var.name}-..."
#
# Add input validation to var.vpc_cidr in variables.tf (hint: can(cidrnetmask(...))).
