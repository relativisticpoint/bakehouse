# Bakehouse

> **Bake once, ship everywhere.**
> A one-day, hands-on course on production-grade Terraform, pipeline-driven deployments, artifact repositories and OS factories.

You will build a tiny internal platform on AWS (`eu-west-3`). A small web service runs on EC2 in an Auto Scaling Group. Everything around it gets the production treatment:

- it boots from a **golden AMI built by your own OS factory** (Packer, hardened, tested, promoted through channels);
- it runs a **container image pulled from your artifact repository** (ECR): scanned, signed, and promoted by digest without rebuilding;
- it is deployed by **Terraform from GitHub Actions**: plan on PR, apply on merge, dev first, prod after approval, no cloud keys stored anywhere.

Rolling out a new OS or app version is a one-line PR. Rolling back is `git revert`.

## Architecture

```
 image/ (Packer) ──► AMI  Channel=candidate ──promote──► Channel=approved ─┐
 app/   (Go)     ──► ECR bakehouse/app-candidates ──promote (same digest)──► ECR bakehouse/app-releases
                        + SBOM + trivy gate + cosign keyless signature      │
 envs/dev|prod (Terraform) ── reads AMI + image digest ─────────────────────┘
        └─► VPC (public subnets, no NAT) → ALB → ASG (1× t4g.micro) via launch template
            instance refresh: the new instance must pass ALB health before the old one dies
```

## The day

| Time | TP | You build | Core lesson |
|---|---|---|---|
| Evening before | [Prep](docs/00-prep.md) | Tools, AWS profile, public repo | Saves ~1h on the day |
| 09:00–09:30 | [TP0 Bootstrap](docs/TP0-bootstrap.md) | S3 state + locking, GitHub OIDC roles | The bootstrap problem; why CI holds no keys |
| 09:30–11:00 | [TP1 Terraform pipeline](docs/TP1-terraform-pipeline.md) | Modules, environments, plan/apply workflow | Infra changes go through code review |
| 11:00–12:30 | [TP2 Artifacts & supply chain](docs/TP2-artifacts.md) | ECR, SBOM, scan gate, signing, promotion | Build once, deploy many; digests not tags |
| 12:30–13:30 | Lunch | *Start the first Packer bake before you eat* | |
| 13:30–15:30 | [TP3 OS factory](docs/TP3-os-factory.md) | Packer AMI, hardening, channels | Immutable infrastructure |
| 15:30–17:00 | [TP4 Deploy](docs/TP4-deploy.md) | ASG + ALB, instance refresh, dev→prod | Pinning, approvals, rolling updates |
| 17:00–18:00 | [TP5 Break it](docs/TP5-break-it.md) | Failure drills and teardown | Production grade means failure paths work |

## How to work through it

1. One **branch and PR per exercise group**. The pipeline is part of what you are learning, so use it from TP1 on.
2. Each TP follows the same shape: **Objectives → Concepts → Exercises → Break it → Checkpoint → Review questions → Going further**.
3. Search for `TODO(TPx.y)` to find what you must write. The skeletons already contain the names and outputs the next TP relies on, so keep them.
4. Hints are collapsed under `<details>`. Try first; open a hint when you've been stuck for ~10 minutes.
5. Don't move on until the **Checkpoint** commands pass.

## Cost

About **$3** for the day (ALB ≈ $0.80, two `t4g.micro`, a few short Packer builds, S3/ECR pennies). No NAT Gateway, by design. Run the teardown in TP5 and the bill stays near zero.

## Repo map

| Path | What |
|---|---|
| `docs/` | Prep + TP0–TP5 |
| `app/` | Finished Go service and Dockerfile. Not a learning target, just something to ship |
| `bootstrap/` | State bucket and GitHub OIDC roles (applied from your laptop) |
| `artifacts/` | ECR repositories (TP2) |
| `modules/network`, `modules/service` | Reusable Terraform modules |
| `envs/dev`, `envs/prod` | Environment compositions |
| `image/` | Packer template and provisioning scripts (the OS factory) |
| `.github/workflows/` | The pipelines |
| `scripts/preflight.sh` | Checks your setup |
