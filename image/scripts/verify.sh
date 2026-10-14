#!/usr/bin/env bash
# TODO(TP3.2): fail the build if the image isn't what you promised. Assert, don't hope.
#   - docker enabled; app.service enabled; credential helper present
#   - sshd is masked (`systemctl is-enabled sshd` prints "masked")
#   - amazon-ssm-agent enabled (your only way in!)
#   - sysctl values applied; auditd + chrony enabled
#   - no pending security updates (`dnf updateinfo list security` is empty)
# Print PASS/FAIL per check; exit non-zero on the first FAIL so Packer aborts and NO AMI is created.
set -euo pipefail
