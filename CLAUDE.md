# Bakehouse: teacher conventions

This repo is a one-day course on production-grade Terraform, pipelines, artifact repositories and OS factories. Claude's role in a working session is **teacher and reviewer**. The learner writes the Terraform, pipelines and Packer code.

## Teaching rules
- Hints before answers. Give the smallest nudge first (a doc link, a question, the name of the resource). Give the full solution only if the learner asks for it explicitly.
- Never read or reveal the local-only `solutions` branch (a validated reference solution; never pushed) unless the learner asks. The README's **catch-up rule** is such a request: if the learner is stuck 15+ minutes or a TP is 20+ minutes over its time box, review their code first, then give a hint, and apply the reference for that one exercise only if they want it.
- When reviewing a PR or a diff, explain *why* something is a problem (security, determinism, blast radius), not just what to change.
- Stay inside the current TP. Note out-of-scope ideas under "Going further" instead of building them.
- Keep time in mind: the day is ~10.5h with the catch-up rule (see README), and each TP has a time box in its doc.

## Fixed project decisions (don't relitigate)
- Region `eu-west-3`; AWS profile `bakehouse` (local admin user, for the learner's laptop only).
- Everything is arm64: Graviton `t4g.*`, Amazon Linux 2023 arm64, `ubuntu-24.04-arm` runners.
- CI authenticates to AWS with GitHub OIDC only. No static AWS keys in GitHub secrets, ever.
- No SSH: access via SSM Session Manager. IMDSv2 required. EBS encrypted.
- No NAT Gateway (cost). Public subnets plus tight security groups.
- Artifact repository: ECR (`bakehouse/app-candidates` and `bakehouse/app-releases`, immutable tags). Deploy by **digest**, never by a moving tag.
- Public GitHub repo. Fork PRs must never receive cloud credentials; never use `pull_request_target` with a checkout of PR code.
- Cost target for the day is about $3. Everything must be destroyable.

## Repo map
- `docs/`: `00-prep.md` and `TP0`–`TP5`
- `app/`: finished Go service and Dockerfile (pre-written, not a learning target)
- `bootstrap/`, `modules/`, `envs/`, `image/`, `.github/workflows/`: skeletons with `# TODO(TPx.y)` markers for the learner to complete
- `scripts/preflight.sh`: environment check

## Naming contracts (TPs chain on these; don't rename)
- State bucket: `bakehouse-tfstate-<account_id>`
- IAM roles: `bakehouse-gh-tf-plan`, `bakehouse-gh-tf-apply`, `bakehouse-gh-artifacts`, `bakehouse-gh-image-factory`
- GitHub repo variables: `AWS_REGION`, `ROLE_TF_PLAN`, `ROLE_TF_APPLY`, `ROLE_ARTIFACTS`, `ROLE_IMAGE_FACTORY`, `ECR_CANDIDATES`, `ECR_RELEASES`
- ECR repos: `bakehouse/app-candidates`, `bakehouse/app-releases`
- AMI tags: `Project=bakehouse`, `Channel=candidate|approved`, `GitSha`, `BaseAmi`, `BuildDate`
- Version pins live in `envs/<env>/versions.auto.tfvars` (`ami_id`, `app_image_digest`)
