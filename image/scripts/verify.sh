#!/usr/bin/env bash
# TODO(TP3.2): fail the build if the image isn't what you promised. Assert, don't hope.
#   - docker enabled; app.service enabled; credential helper present
#   - sshd is masked (`systemctl is-enabled sshd` prints "masked")
#   - amazon-ssm-agent enabled (your only way in!)
#   - sysctl values applied; auditd + chrony enabled
#   - no pending security updates: `dnf -q check-update --security --releasever=latest` exits 100 when updates
#     exist (0 = none). Assert on the exit code; parsing `updateinfo` output is fragile (it prints a metadata line)
#   - do NOT assert net.ipv4.ip_forward: Docker hasn't started yet, so it is 0 at build time
# Print PASS/FAIL per check; exit non-zero on the first FAIL so Packer aborts and NO AMI is created.
set -euo pipefail
