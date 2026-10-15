# TP1: Terraform pipeline (09:30–11:15)

## Objectives
- Write a reusable **module** and compose it into two environments.
- Make infrastructure changes follow the same path as code: branch → PR → automated checks → plan visible in the PR → review → merge → apply.
- Put a **human approval** between dev and prod.

Work in `modules/network/`, `envs/dev/`, `envs/prod/`, `.github/workflows/terraform.yml`.

## Concepts (≈10 min)

**Modules** are functions for infrastructure: inputs (`variable`), outputs, and a clear contract. A module should do one thing (`network`: a VPC and public subnets) and know nothing about its callers. We keep modules local in `modules/` today; in real life you version them (git tags or a registry) so that prod can pin `v1.4.0` while dev tries `v1.5.0-rc1`.

**Environments: directories, not workspaces.** Each env is a directory with its own backend key, its own variables and its own blast radius. Workspaces share code *and* backend configuration, which makes "I'm in the wrong workspace" accidents easy. Duplicated 20-line compositions are a fair price for clarity.

**Pinning, at three levels.**
- `required_version` (Terraform) and `required_providers` with `~>` constraints;
- `.terraform.lock.hcl`: **commit it**. It records provider hashes. Generate hashes for every platform that will run it: your Mac *and* the Linux CI runner (plus `linux_amd64` in case a runner label changes):
  `terraform providers lock -platform=darwin_arm64 -platform=linux_arm64 -platform=linux_amd64`
- CI runs `terraform init -lockfile=readonly` so it can never silently upgrade a provider.

**Plan on PR, apply on merge.** The reviewer approves a *plan*, not just code. Two rules make this safe:
1. *Apply the plan you reviewed*: `plan -out=tfplan` then `apply tfplan`.
2. Never apply from a laptop in the normal flow.

**Public-repo security rules for workflows** (this repo is public):
- Fork PRs never receive OIDC tokens or secrets. Good. Don't "fix" that.
- **Never** use `pull_request_target` together with checking out the PR's code.
- Default `permissions: contents: read`; grant `id-token: write` only on jobs that need it.
- Third-party actions: pin by version (SHA pinning is the gold standard, a "Going further" item).

## Exercises

### TP1.1: `modules/network`
Implement the module against the contract in `variables.tf` and `outputs.tf`: a VPC, `az_count` public subnets (one per AZ), internet gateway, public route table. **No NAT Gateway.** Add a `validation` block on `vpc_cidr`.

<details><summary>Hint: subnets across AZs</summary>

`data "aws_availability_zones" "available" { state = "available" }`, then `count = var.az_count`, `availability_zone = data.aws_availability_zones.available.names[count.index]`, `cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)`.
</details>
<details><summary>Hint: validation</summary>

`condition = can(cidrnetmask(var.vpc_cidr))`
</details>

Uncomment the outputs.

### TP1.2: Wire dev and prod
In each `envs/<env>/main.tf` call the module with `name = "bakehouse-<env>"` and `var.vpc_cidr` (set in `terraform.tfvars`). Finish `backend.tf` with the key `envs/<env>/terraform.tfstate`, `region`, `encrypt`, `use_lockfile`; the bucket is passed at init time.

Run it locally once to check your work (read-only apart from a plan):

```bash
cd envs/dev
terraform init -backend-config="bucket=bakehouse-tfstate-$(aws sts get-caller-identity --query Account --output text)"
terraform plan
```

Then generate the multi-platform lock files in **every stack directory** (both `envs/`, `bootstrap/`, and later `artifacts/`; CI's `init -lockfile=readonly` fails without one) and commit them:

```bash
terraform providers lock -platform=darwin_arm64 -platform=linux_arm64 -platform=linux_amd64
```

Do **not** run `apply` from your laptop. The pipeline does that.

> The skeleton ships a placeholder `app_image_digest` (all zeros) so that `plan` works before you have an image, and a `.tflint.hcl` that silences "unused variable" warnings until TP4 (when the service module starts using them). Both carry `TODO(TP4…)` comments.

### TP1.3: The workflow
Complete `.github/workflows/terraform.yml`. Required behaviour:

| Event | Job | What it does |
|---|---|---|
| PR | `checks` | `terraform fmt -check -recursive`, `tflint`, `trivy config`, and `terraform validate` (with `init -backend=false`) for each stack |
| PR | `gate` | Fails if `checks` or `plan` failed. The **only** check branch protection requires (see TP1.4) |
| PR | `plan` (matrix: dev, prod) | OIDC → `ROLE_TF_PLAN`, `init -lockfile=readonly -backend-config=...`, `plan -out`, **post the plan as a PR comment** |
| push to main | `apply-dev` | OIDC → `ROLE_TF_APPLY` (environment `dev`), plan then apply the same plan file |
| push to main | `apply-prod` | same, but environment `prod` (approval required) and only after dev succeeded |

<details><summary>Hint: assume the role</summary>

`aws-actions/configure-aws-credentials@v4` with `role-to-assume: ${{ vars.ROLE_TF_PLAN }}` and `aws-region: ${{ vars.AWS_REGION }}`. The job needs `permissions: id-token: write`.
</details>
<details><summary>Hint: bucket name without hardcoding it</summary>

`ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)` then `terraform init -backend-config="bucket=bakehouse-tfstate-${ACCOUNT_ID}" -lockfile=readonly`.
</details>
<details><summary>Hint: plan comment</summary>

`hashicorp/setup-terraform@v3` installs a wrapper that mangles `terraform show > file` and `-detailed-exitcode`: set `terraform_wrapper: false`. Then `terraform show -no-color tfplan > plan.txt`. `gh pr comment` creates a **new** comment per push; to update in place, put a hidden marker (`<!-- plan:envs/dev -->`) in the body, list the PR's comments through the REST API, and `PATCH /repos/{owner}/{repo}/issues/comments/{id}` if the marker exists. Needs `GH_TOKEN: ${{ github.token }}` and `pull-requests: write`. Comments are limited to 65,536 characters: truncate.
</details>
<details><summary>Hint: trivy and tflint</summary>

`aquasecurity/setup-trivy` (pin its version) then `trivy config --exit-code 1 --severity HIGH,CRITICAL .`. For tflint: `terraform-linters/setup-tflint`, then `tflint --recursive --config "$GITHUB_WORKSPACE/.tflint.hcl"`. The **absolute** `--config` matters: in recursive mode a relative or implicit config is not found in sub-directories, and you'd get warnings the config was meant to silence. tflint exits non-zero on *warnings*, not only errors. Run both locally first.
</details>

Run `actionlint` before you push: `actionlint`.

**Expect friction**: the first OIDC run will probably fail with `Not authorized to perform sts:AssumeRoleWithWebIdentity`. Read the `sub` the job *actually* presents (the error and the job log show it) and compare it with your trust policy. This is the most valuable debugging skill of the day.

### TP1.4: Environments and branch protection
Create the GitHub environments and protect `main`. Open at least one PR *first* (protection can only require checks that have run once).

Order matters: **protect `main` first**, because an environment restricted to protected branches refuses even `main` until it is protected.

```bash
OWNER=$(gh api user -q .login); UID_=$(gh api user -q .id)

# 1. Branch protection: require the `gate` job (only), block force-push, no required reviews (you are alone)
gh api -X PUT repos/$OWNER/bakehouse/branches/main/protection --input - <<JSON
{ "required_status_checks": { "strict": false, "checks": [ { "context": "gate" } ] },
  "enforce_admins": false, "required_pull_request_reviews": null, "restrictions": null,
  "allow_force_pushes": false }
JSON

# 2. Environments. BOTH are limited to protected branches: otherwise a workflow on any feature branch
#    could say `environment: dev` and assume the apply role.
gh api -X PUT repos/$OWNER/bakehouse/environments/dev --input - <<JSON
{ "deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false } }
JSON
gh api -X PUT repos/$OWNER/bakehouse/environments/prod --input - <<JSON
{ "reviewers": [ { "type": "User", "id": $UID_ } ],
  "deployment_branch_policy": { "protected_branches": true, "custom_branch_policies": false } }
JSON
```

Open a PR **first**: protection can only require checks that have run at least once. Two traps worth knowing: a matrix job's check is named `plan (envs/dev)`, not `plan`, and a workflow with a `paths:` filter never starts for a PR that doesn't match, leaving a required check forever "waiting". That is why the skeleton has no `paths:` filter on `pull_request` and why you require the single `gate` job. A *skipped* job counts as passing, so `gate` must also fail when a needed job is cancelled or failed.

Add an `if: github.ref == 'refs/heads/main'` to every apply job as a second lock. (Discuss why "no required reviews" is a limitation of working alone, not a best practice.)

## Break it
1. **Insecure by commit.** In a PR, add to `envs/dev/main.tf` a security group with ingress on port 22 from `0.0.0.0/0`. Watch `trivy config` fail the PR. Remove it.
2. **Format drift.** Push a badly indented `.tf` file. Watch `fmt -check` fail.
3. **Prove the gate.** Merge a harmless change (a new tag) and watch `apply-prod` sit in *Waiting for review* until you approve it.
4. **Provider float.** Delete `.terraform.lock.hcl` from a PR and see what `-lockfile=readonly` does.

## Checkpoint
- A merged PR whose conversation shows a **plan comment** for dev and prod.
- The Actions run shows `apply-dev` ✅, then `apply-prod` waited for your click.
- `aws ec2 describe-vpcs --filters Name=tag:Project,Values=bakehouse --query 'Vpcs[].[Tags[?Key==`Env`]|[0].Value,CidrBlock]'` returns both VPCs.
- `aws s3 ls s3://bakehouse-tfstate-<acct>/envs/ --recursive` shows two state files.
- No AWS credential exists in the repo's secrets: `gh secret list` is empty.

## Review questions
1. Why `plan -out` + `apply tfplan` rather than a plain `apply` in the apply job?
2. What can go wrong if the lock file only contains `darwin_arm64` hashes?
3. Someone opens a PR from a fork. What happens to the `plan` job, and is that what you want? (Careful: a *skipped* job counts as passing for a required check. What stops the PR from merging anyway?)
4. Why is the `prod` plan generated at PR time potentially different from what applies after merge, and how would you reduce that gap?
5. What would you lose by using workspaces instead of directories? What would you gain?

## Going further (cut for time)
- Publish `modules/*` as versioned modules and have prod pin an older tag than dev.
- `terraform test` for the network module.
- Pin all actions to commit SHAs, and use Renovate/Dependabot to update them.
- Required review via CODEOWNERS on `envs/prod/**`.
