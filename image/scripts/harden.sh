#!/usr/bin/env bash
# TODO(TP3.2): pragmatic "CIS-lite" hardening.
#   - security patches first (patching an image = rebuilding it). AL2023 repos are versioned and dnf stays on
#     the release the AMI shipped with, so a plain `dnf upgrade --security` can be a no-op:
#     use `dnf -y upgrade --security --releasever=latest`
#   - sysctl drop-in in /etc/sysctl.d/: rp_filter, no ICMP redirects, no source routing, tcp_syncookies
#     (careful: don't turn off IP forwarding, Docker needs it)
#   - auditd installed and enabled, chrony enabled
#   - dnf clean all
#   - LAST STEP: `systemctl disable sshd` + `systemctl mask sshd`. Do NOT use --now / stop it:
#     Packer is still connected over SSH and runs verify.sh next. A masked service keeps running until
#     the build instance shuts down, but never starts again on any instance booted from the image.
#     From then on the only way in is SSM Session Manager.
#   - remove /etc/ssh/ssh_host_* so the image carries no host identity
set -euo pipefail
