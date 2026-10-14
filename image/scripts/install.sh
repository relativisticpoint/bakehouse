#!/usr/bin/env bash
# TODO(TP3.2): install what the instance needs, and nothing else.
#   - docker (dnf), enable the service
#   - the ECR credential helper, and /root/.docker/config.json with {"credsStore": "ecr-login"}
#   - move /tmp/app.service to /etc/systemd/system/app.service, `systemctl enable app`
#     (enable it but don't start it: there is no /etc/bakehouse/app.env yet. user-data writes it at boot)
#   - mkdir -p /etc/bakehouse
set -euo pipefail
