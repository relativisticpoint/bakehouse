# Prep: the evening before (~45 min)

Goal: wake up and start TP0 without installing anything. Finish by running `./scripts/preflight.sh` until it's all green.

## 1. Install the tools

```bash
brew install hashicorp/tap/terraform hashicorp/tap/packer tflint trivy cosign syft actionlint crane jq awscli gh
brew install --cask session-manager-plugin
```

| Tool | Used for |
|---|---|
| terraform | Infrastructure as code (needs ≥ 1.11 for S3-native state locking) |
| packer | Building AMIs (TP3) |
| tflint, trivy | Linting and security scanning (TP1, TP2, TP3) |
| cosign, syft, crane | Signing, SBOMs and registry copies (TP2) |
| actionlint | Catches workflow mistakes before you push |
| jq | Reading Terraform/AWS JSON output in shell |
| awscli, gh | AWS and GitHub command lines (`python3` is also needed by `preflight.sh`; macOS ships it) |
| session-manager-plugin | Shell access to instances without SSH (TP4) |

Docker must be running too (OrbStack or Docker Desktop).

## 2. AWS profile (simplified for the day)

For speed we use a **local admin IAM user**. This is a deliberate shortcut.

1. AWS Console → IAM → Users → **Create user** `bakehouse-admin` (no console access needed).
2. Attach the policy `AdministratorAccess`.
3. Security credentials → **Create access key** → use case *Command Line Interface*.
4. On your laptop:
   ```bash
   aws configure --profile bakehouse
   #   region: eu-west-3, output: json
   export AWS_PROFILE=bakehouse      # add to your shell for the day
   aws sts get-caller-identity       # must print your account
   ```
5. Check the default VPC exists (Packer uses it in TP3):
   ```bash
   aws ec2 describe-vpcs --region eu-west-3 --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId'
   # if null: aws ec2 create-default-vpc --region eu-west-3
   ```
6. Recommended, 30 seconds: a $10 budget alarm.
   ```bash
   BUDGET_EMAIL=you@example.com ./scripts/preflight.sh --budget
   ```

> **What we skipped, and why it matters**
> - Long-lived admin keys on a laptop are one of the most common causes of cloud breaches. In a real organisation you use IAM Identity Center (SSO) with short-lived credentials, MFA everywhere, and no IAM users.
> - **The pipelines never use these keys.** From TP0 on, GitHub Actions authenticates with OIDC. That part is done properly.
> - At the end of the day (TP5) you will **deactivate and delete this access key**.

## 3. GitHub: a public repo

The repo is public: anything you commit is public. Never commit state files, keys or `.env` files (`.gitignore` already blocks the usual suspects).

```bash
cd ~/Documents/from_dev_to_prod
gh auth status || gh auth login
git add -A && git commit -m "Bakehouse scaffold"     # skip if already committed
gh repo create bakehouse --public --source=. --remote=origin --push
```

> **Never push every branch.** This repo may contain a local-only `solutions` branch with a reference solution. `gh repo create --push` pushes the current branch only, which is what you want. Don't run `git push --all` or `git push --mirror`, or you publish the answers (and a public repo can't take them back).

Harden the repo's Actions settings (this matters because the repo is public):

```bash
OWNER=$(gh api user -q .login)
# Default GITHUB_TOKEN to read-only
gh api -X PUT "repos/$OWNER/bakehouse/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
# Fork PRs need maintainer approval before any workflow runs
gh api -X PUT "repos/$OWNER/bakehouse/actions/permissions/fork-pr-contributor-approval" \
  -f approval_policy=all_external_contributors
```

> If a call errors (e.g. 409 because an organisation policy forbids it), set the same options in the UI: *Settings → Actions → General*.

## 4. Run the check

```bash
./scripts/preflight.sh
```

Every line should be green. Fix what isn't, then rerun. You are ready for [TP0](TP0-bootstrap.md).
