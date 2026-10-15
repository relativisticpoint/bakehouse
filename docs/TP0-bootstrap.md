# TP0: Bootstrap (08:30–09:30)

## Objectives
By the end you can explain, and have built:
- a remote, versioned, locked Terraform state in S3;
- a way to resolve the chicken-and-egg problem ("Terraform needs a bucket; the bucket should be created by Terraform");
- a trust relationship between GitHub Actions and AWS with **no stored credentials**, and four least-privilege roles that use it.

Work in `bootstrap/`. This stack is applied **from your laptop**, never from the pipeline.

## Concepts (≈10 min)

**State is the source of truth.** Terraform maps your code to real resources through the state file. Lose it and Terraform wants to recreate everything. Corrupt it and it may destroy things. Two people writing it at once corrupt it. So production state must be: remote, versioned (to recover), encrypted (it contains secrets in plain text), and **locked** during operations.

**Locking.** Since Terraform 1.10, the S3 backend can lock natively with `use_lockfile = true`: it writes a `<key>.tflock` object using S3 conditional writes. (Older setups used a DynamoDB table; you'll still see it in the wild.)

**The bootstrap problem.** The state bucket must exist before any stack can use it as a backend. The standard answer: a tiny `bootstrap` stack that starts with **local** state, creates the bucket, then migrates its own state into that bucket (`init -migrate-state`). From then on it is just another stack. Everything else is created by pipelines.

**OIDC federation instead of access keys.** A static `AWS_ACCESS_KEY_ID` in GitHub secrets is a credential that never expires, can be exfiltrated by any workflow step, and must be rotated by humans. With OIDC:
1. the workflow asks GitHub for a short-lived signed token (a JWT);
2. the token says *who is asking*: the `sub` claim, e.g. `repo:<owner>/bakehouse:ref:refs/heads/main`;
3. AWS validates the signature against GitHub's public keys and checks the role's **trust policy**;
4. if it matches, AWS returns temporary credentials (1 hour by default).

The `sub` claim looks different depending on how the job was triggered:

| Trigger | `sub` |
|---|---|
| push / dispatch on main | `repo:OWNER/bakehouse:ref:refs/heads/main` |
| pull request | `repo:OWNER/bakehouse:pull_request` |
| job using an `environment` | `repo:OWNER/bakehouse:environment:<name>` |

A job that declares an `environment:` presents **only** the environment form of `sub`, never the branch form. `workflow_dispatch` and `schedule` jobs present the branch form. The `sub` comparison is case-sensitive: use your login exactly as `gh api user -q .login` prints it.

**Why four roles?** One role per job family, so a compromise or a bug has a small blast radius:

| Role | Used by | Can do | Trusted from |
|---|---|---|---|
| `bakehouse-gh-tf-plan` | PR plans | **Read-only** + write the lock object | `pull_request`, `main` |
| `bakehouse-gh-tf-apply` | merge applies | Create/modify the project's infra | `environment:dev`, `environment:prod` |
| `bakehouse-gh-artifacts` | app build + promotion | Push/pull ECR | `main` |
| `bakehouse-gh-image-factory` | Packer + AMI promotion | EC2 image building / tagging | `main` |

Think about this one: the **plan** role runs on PRs, and a plan executes code from the PR (providers, `external` data sources). Whatever that role can do, *any PR author with write access* can do. That's why it is read-only.

## Exercises

### TP0.1: The state bucket
In `bootstrap/main.tf`, create `bakehouse-tfstate-<account_id>` (use `data.aws_caller_identity.current`). It needs versioning, default encryption, a public access block (all four flags), and `lifecycle { prevent_destroy = true }`.

<details><summary>Hint: resources</summary>

`aws_s3_bucket`, `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration` (AES256 is fine), `aws_s3_bucket_public_access_block`. Bonus: a bucket policy denying requests where `aws:SecureTransport` is `false`.
</details>

```bash
cd bootstrap
terraform init
terraform apply -var github_owner=$(gh api user -q .login)
```

Read the plan before typing `yes`. Always.

### TP0.2: Move the state into the bucket
Add the `backend "s3"` block in `bootstrap/versions.tf`:
`bucket`, `key = "bootstrap/terraform.tfstate"`, `region`, `encrypt = true`, `use_lockfile = true`. Then:

```bash
terraform init -migrate-state      # answer yes
ls terraform.tfstate*              # local file should now be empty/backup only
aws s3 ls s3://bakehouse-tfstate-<account_id>/bootstrap/
```

Backend blocks can't use variables, so the bucket name is a literal here. Discuss: is an account ID in a public repo a problem? (Short answer: it's not a secret, but you should know why people still avoid it, and how `-backend-config` avoids it. That's what envs do in TP1.)

### TP0.3: OIDC provider and four roles
Create:
1. `aws_iam_openid_connect_provider` for `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
2. The four roles from the table above. Each **trust policy** must have: principal = the OIDC provider, action `sts:AssumeRoleWithWebIdentity`, a condition on `…:aud` **and** a condition on `…:sub` restricted to your repo.
3. Permissions:
   - `tf-plan`: managed `ReadOnlyAccess` + an inline policy: read the state bucket, and `GetObject`/`PutObject`/`DeleteObject` only on `*.tflock` keys (it reads the lock to tell you who holds it). Be aware that `ReadOnlyAccess` already reads every bucket: the inline statement documents intent more than it restricts.
   - `tf-apply`: `PowerUserAccess` (no IAM) + an inline policy allowing IAM role / instance-profile / policy management **only** on resources named `bakehouse-dev-*` and `bakehouse-prod-*`, plus full access to the state bucket. It cannot edit the `bakehouse-gh-*` roles: CI must not be able to rewrite its own permissions. Be honest about the limit, though: it can still write *any* policy document onto `bakehouse-dev-*` roles, so a PR author who can change the module can give an instance role more power. The real fix is a **permissions boundary** on every role the pipeline creates (see Going further).
   - `artifacts`: ECR push and pull on `arn:aws:ecr:eu-west-3:<acct>:repository/bakehouse/*` plus `ecr:GetAuthorizationToken`. (The repos don't exist yet; that's fine, IAM doesn't check.)
   - `image-factory`: what Packer's `amazon-ebs` builder needs (the "IAM Task or Instance Role" section of the **README of the Packer amazon plugin**; about 33 EC2 actions), plus `ec2:DescribeVpcs` and `ec2:DescribeInstanceTypeOfferings` (default-VPC builds), `ssm:GetParameter` on the AL2023 public parameter, and `EnableImageDeprecation` for promotion. Start broad (all of these on `*`); tightening by tag happens in TP3 and depends on how Packer tags (see TP3). You will iterate on this.

<details><summary>Hint: trust policy shape</summary>

Use `data "aws_iam_policy_document"` with a `principals { type = "Federated" ... }` block and two `condition` blocks, both `test = "StringEquals"`, variables `token.actions.githubusercontent.com:aud` and `token.actions.githubusercontent.com:sub`. The `values` of the `sub` condition is a list: you can allow several subjects.
</details>

<details><summary>Hint: sub values</summary>

`repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main`, `repo:${var.github_owner}/${var.github_repo}:pull_request`, `repo:${var.github_owner}/${var.github_repo}:environment:dev`.
</details>

### TP0.4: Hand the role ARNs to GitHub
Uncomment the outputs in `bootstrap/outputs.tf`, apply, then:

```bash
gh variable set AWS_REGION         --body eu-west-3
gh variable set ROLE_TF_PLAN       --body "$(terraform output -json role_arns | jq -r .tf_plan)"
gh variable set ROLE_TF_APPLY      --body "$(terraform output -json role_arns | jq -r .tf_apply)"
gh variable set ROLE_ARTIFACTS     --body "$(terraform output -json role_arns | jq -r .artifacts)"
gh variable set ROLE_IMAGE_FACTORY --body "$(terraform output -json role_arns | jq -r .image_factory)"
gh variable list
```

They are *variables*, not secrets. A role ARN isn't sensitive; the protection is the trust policy.

Commit on a branch, open a PR, merge. (No pipeline checks exist yet; TP1 adds them.)

## Break it
1. **Hold the lock.** In `bootstrap/`, run `terraform apply` and **don't answer the prompt**. In a second terminal run `terraform plan`. Read the error. Look at the lock object: `aws s3 ls s3://bakehouse-tfstate-<acct>/bootstrap/`. Then answer `no` in the first terminal and confirm the lock disappears.
2. **Try to destroy.** `terraform destroy`. What stops you? Which line of code?
3. **(Optional, 5 min) Wrong repo.** Create a throwaway public repo with a workflow that runs `aws-actions/configure-aws-credentials` with your `ROLE_TF_PLAN` ARN. Read the failure. Which condition rejected it? Delete the repo afterwards.

## Checkpoint
```bash
aws s3api get-bucket-versioning --bucket bakehouse-tfstate-<acct>      # Status: Enabled
aws s3 ls s3://bakehouse-tfstate-<acct>/bootstrap/                     # terraform.tfstate present
for r in tf-plan tf-apply artifacts image-factory; do aws iam get-role --role-name bakehouse-gh-$r --query 'Role.Arn'; done
gh variable list                                                       # 5 variables
terraform plan -var github_owner=<you>                                 # "No changes."
```

## Review questions
1. Why can't the bootstrap stack be applied by the pipeline? What would an attacker gain if it could?
2. A teammate proposes checking only `aud` in the trust policy "because it's simpler". What exactly becomes possible?
3. Why does the *plan* role need write access to anything at all?
4. Versioning is on, but someone deletes the latest `terraform.tfstate`. How do you recover?
5. What is stored in plain text in a state file, and what does that imply for who may read the bucket?

## Going further (cut for time)
- Separate AWS accounts per environment (the real production answer) and AWS Organizations SCPs.
- IAM Identity Center for humans instead of an IAM user.
- A role per environment for apply (`tf-apply-dev`, `tf-apply-prod`), so a dev job can never touch prod.
- **Permissions boundaries** (`iam:PermissionsBoundary` condition on `CreateRole`/`PutRolePolicy`) so that even a compromised pipeline cannot mint a role more powerful than the boundary.
- A bucket lifecycle rule for expired delete markers: every lock release on a versioned bucket leaves one.
- State bucket replication / MFA-delete for disaster recovery.
