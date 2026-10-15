# Service module: ALB + Auto Scaling Group of golden-AMI instances running the app container.
#
# TODO(TP4.1): create
#   Security groups: write the rules INLINE (ingress {} / egress {}), TP5 drill 3 (drift) depends on it:
#     rules defined as separate aws_vpc_security_group_*_rule resources are invisible to drift detection
#     of the group. Two groups referencing each other inline create a dependency cycle: make the ALB's
#     egress rule a standalone aws_vpc_security_group_egress_rule to break it.
#     - alb:      80 from 0.0.0.0/0, egress to the instance SG only
#     - instance: 80 from the ALB SG ONLY. No port 22. Egress 443 (ECR, SSM) + whatever you need.
#   Load balancer
#     - aws_lb (application, public subnets), listener :80 -> target group
#     - aws_lb_target_group on port 80, health check path /health
#   Instance identity
#     - IAM role + instance profile "${var.name}-instance"
#       * AmazonSSMManagedInstanceCore (Session Manager, replaces SSH)
#       * ECR read, scoped to var.ecr_repository_arns (+ ecr:GetAuthorizationToken on "*")
#   Compute
#     - aws_launch_template
#         image_id = var.ami_id, arm64 instance type, IMDSv2 required
#         (http_tokens = "required", and think about http_put_response_hop_limit: the app
#          runs in a container and reads instance metadata, one extra network hop),
#         encrypted EBS, instance profile, SG, user_data (see below)
#     - aws_autoscaling_group   (max_size = 2 * desired: the refresh surges to double capacity)
#         health_check_type = "ELB", target_group_arns, desired = var.desired_capacity,
#         launch_template version = latest_version (so a new AMI triggers a refresh),
#         instance_refresh { strategy = "Rolling", preferences { ... } }
#
# user_data = LAST-MILE CONFIG ONLY. It writes /etc/bakehouse/app.env with:
#     APP_IMAGE=${var.app_image}
#     APP_ENV=${var.env}
#   and runs: systemctl restart app   (the unit ships in the AMI, see image/files/app.service)
#   Nothing is installed at boot. That's the whole point of the golden image.
