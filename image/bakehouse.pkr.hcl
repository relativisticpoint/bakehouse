# The OS factory: builds the Bakehouse golden AMI (Amazon Linux 2023, arm64).
#
# TODO(TP3.1): fill in
#   packer { required_plugins { amazon = { source = "github.com/hashicorp/amazon", version = "~> 1.3" } } }
#   variables: git_sha (default "local"), region (default "eu-west-3")
#   data "amazon-parameterstore": the AL2023 arm64 base AMI, from the public SSM parameter
#       /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64
#   source "amazon-ebs" "bakehouse":
#       instance_type t4g.small, ssh_username ec2-user, default VPC (no vpc_id needed),
#       imds_support = "v2.0", encrypt_boot = true,
#       temporary_security_group_source_public_ip = true  (SSH from this machine only, only during the build)
#       ami_name = "bakehouse-${var.git_sha}-${local.ts}"   (local.ts: regex_replace(timestamp(), "[- TZ:]", ""))
#       tags: Project=bakehouse, Channel=candidate, GitSha, BaseAmi, BuildDate
#       snapshot_tags: same tags (otherwise orphan snapshots are untraceable)
#       run_tags + run_volume_tags: at least Project=bakehouse. Packer tags the builder instance, volumes and
#       the AMI AT CREATION from run_tags; `tags` are applied afterwards. Tag-scoped IAM (TP3.3) depends on it.
#   build { sources, provisioner "file" for files/app.service (to /tmp), then shell scripts as root
#           (execute_command = "sudo -E bash '{{ .Path }}'") in order: install.sh -> harden.sh -> verify.sh,
#           then a FINAL inline provisioner that removes ~ec2-user/.ssh/authorized_keys (the build's temporary key) }
