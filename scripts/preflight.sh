#!/usr/bin/env bash
# Bakehouse preflight: checks your machine and AWS/GitHub setup.
#   ./scripts/preflight.sh            run all checks
#   ./scripts/preflight.sh --budget   also create a $10/month budget alarm (needs BUDGET_EMAIL)
set -uo pipefail

PROFILE="${AWS_PROFILE:-bakehouse}"
REGION="eu-west-3"
fail=0

ok()   { printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$1"; fail=1; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

echo "== Tools =="
for tool in terraform packer tflint trivy cosign syft actionlint docker gh aws session-manager-plugin crane jq; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
  else
    bad "$tool missing (see docs/00-prep.md)"
  fi
done

echo "== Docker daemon =="
if docker info >/dev/null 2>&1; then ok "docker daemon running"; else bad "docker daemon not running"; fi

echo "== AWS =="
export AWS_PROFILE="$PROFILE"
if identity=$(aws sts get-caller-identity --output json 2>/dev/null); then
  account=$(printf '%s' "$identity" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Account"])')
  arn=$(printf '%s' "$identity" | python3 -c 'import json,sys; print(json.load(sys.stdin)["Arn"])')
  ok "profile '$PROFILE' works: $arn"
  configured_region=$(aws configure get region 2>/dev/null || true)
  if [ "$configured_region" = "$REGION" ]; then ok "region $REGION"; else bad "profile region is '${configured_region:-unset}', expected $REGION"; fi
  default_vpc=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=is-default,Values=true \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
  if [ "$default_vpc" != "None" ] && [ -n "$default_vpc" ]; then
    ok "default VPC exists in $REGION ($default_vpc), needed by Packer in TP3"
  else
    bad "no default VPC in $REGION (fix: aws ec2 create-default-vpc --region $REGION)"
  fi
else
  bad "cannot call AWS with profile '$PROFILE' (run: aws configure --profile $PROFILE)"
  account=""
fi

echo "== GitHub =="
if gh auth status >/dev/null 2>&1; then
  ok "gh authenticated as $(gh api user -q .login 2>/dev/null)"
else
  bad "gh not authenticated (run: gh auth login)"
fi
if git remote get-url origin >/dev/null 2>&1; then
  ok "git remote origin: $(git remote get-url origin)"
else
  warn "no git remote 'origin' yet (create the public repo and push; see docs/00-prep.md)"
fi

if [ "${1:-}" = "--budget" ]; then
  echo "== Budget alarm =="
  if [ -z "${account:-}" ]; then
    bad "need working AWS credentials first"
  elif [ -z "${BUDGET_EMAIL:-}" ]; then
    bad "set BUDGET_EMAIL=you@example.com and re-run"
  else
    if aws budgets create-budget --account-id "$account" \
      --budget '{"BudgetName":"bakehouse-10usd","BudgetLimit":{"Amount":"10","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
      --notifications-with-subscribers "[{\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":80,\"ThresholdType\":\"PERCENTAGE\"},\"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"$BUDGET_EMAIL\"}]}]" \
      >/dev/null 2>&1; then
      ok "budget 'bakehouse-10usd' created (alerts at 80% to $BUDGET_EMAIL)"
    else
      warn "budget not created (it may already exist, or the IAM user lacks billing access)"
    fi
  fi
fi

echo
if [ "$fail" -eq 0 ]; then
  printf '\033[32mAll green. You are ready for TP0.\033[0m\n'
else
  printf '\033[31mSome checks failed. Fix them using docs/00-prep.md, then re-run.\033[0m\n'
  exit 1
fi
