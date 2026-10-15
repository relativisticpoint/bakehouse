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
| 08:30–09:30 | [TP0 Bootstrap](docs/TP0-bootstrap.md) | S3 state + locking, GitHub OIDC roles | The bootstrap problem; why CI holds no keys |
| 09:30–11:15 | [TP1 Terraform pipeline](docs/TP1-terraform-pipeline.md) | Modules, environments, plan/apply workflow | Infra changes go through code review |
| 11:15–13:00 | [TP2 Artifacts & supply chain](docs/TP2-artifacts.md) | ECR, SBOM, scan gate, signing, promotion | Build once, deploy many; digests not tags |
| 13:00–13:45 | Lunch | *Start the first Packer bake before you eat* | |
| 13:45–16:00 | [TP3 OS factory](docs/TP3-os-factory.md) | Packer AMI, hardening, channels | Immutable infrastructure |
| 16:00–18:00 | [TP4 Deploy](docs/TP4-deploy.md) | ASG + ALB, instance refresh, dev→prod | Pinning, approvals, rolling updates |
| 18:00–19:00 | [TP5 Break it](docs/TP5-break-it.md) | Failure drills and teardown | Production grade means failure paths work |

## Time reality check

The reference solution was built end to end and validated offline. Writing it unaided takes longer than a naive 9 hours: the code you write is ~2,500 lines (HCL, YAML, shell), and some waits can't be shortened (Packer bakes ~10 min each, ALB/ASG creation ~5 min per environment, every PR cycle ~5 min). Plan for **~10.5 hours of work** with the catch-up rule below; unaided, 12 hours or **two half-days** (TP0–TP2, then TP3–TP5) are more comfortable. The TPs are chained, but each ends at a clean checkpoint, so splitting between TP2 and TP3 is natural.

**Catch-up rule.** If you've been stuck on one exercise for 15+ minutes, or a TP is more than 20 minutes over its time box, ask your teacher (Claude) to review your code and give a hint, or to apply the validated reference for *that exercise only*. A working platform at 19:00 beats a perfect TP1 and no TP4. When you're running late, cut in this order: TP5 drill 3, TP4.4's second half, TP3's IAM iteration (ask for the policy), TP1's bonus plan-artifact flow.

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
