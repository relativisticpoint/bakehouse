# TP3: The OS factory (13:30–15:30)

> **Tip:** do TP3.1 before lunch so the first bake runs while you eat. Bakes take ~8–12 minutes, and waiting on them is where this TP's time goes.

## Objectives
- Explain the **golden image** model and why patching means *rebuilding*, not logging in.
- Build a hardened Amazon Linux 2023 arm64 AMI with Packer, and make the build **fail** if the result isn't what you promised.
- Run the build from a pipeline and move images through **channels**: `candidate` → `approved`.

Work in `image/`, `.github/workflows/image.yml`, `.github/workflows/promote-image.yml`.

## Concepts (≈10 min)

**Mutable vs immutable servers.** A mutable server is configured over time (SSH in, install, patch, tweak) until nobody knows what is on it. An immutable one is built from a known recipe, replaced rather than modified, and thrown away. An "OS factory" is the machinery that produces those images continuously: a pipeline that builds, tests, scans, versions and publishes a base image for every team.

**Bake vs fry.** What goes *in* the image ("baked": OS patches, Docker, agents, hardening, the systemd unit) versus what is applied at boot ("fried": environment name, which app version). Rule of thumb: bake everything slow, large or security-relevant, fry only the small, environment-specific bits. Our split: the AMI contains Docker and `app.service`; user-data (TP4) only writes `/etc/bakehouse/app.env` with the image digest and environment.

**Provenance of the base.** Your image is only as trustworthy as its parent. We start from Amazon's official AL2023 image, found through a *public SSM parameter* (`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64`), which always points at the current AMI. Record the parent AMI id in the tags so every image is traceable.

**Hardening, pragmatically.** CIS benchmarks have hundreds of rules; we do a "CIS-lite" subset with the best value: patched OS, sane kernel parameters, auditing, time sync, **no SSH** (access is via SSM Session Manager; fewer doors, and every session is logged), nothing unnecessary installed.

**Channels.** A new image is a `candidate`. Only after checks pass and a human/pipeline decision does it become `approved`. Consumers (dev, via a data source) look only at `approved`. Old approved images get **deprecated** (hidden from default lookups, still launchable), not deleted. This is how Artifactory-style promotion looks for AMIs.

**Patch cadence.** A monthly scheduled rebuild (already in `image.yml`) means the fleet is at most a month behind upstream security patches, with zero SSH sessions.

## Exercises

### TP3.1: `bakehouse.pkr.hcl`
Follow the TODO comment at the top of the file. Required properties:

- base AMI looked up from the SSM parameter (not hardcoded);
- instance type `t4g.small`, builds in the **default VPC**, SSH limited to the builder's own public IP via a temporary security group;
- IMDSv2 only (`imds_support = "v2.0"`), encrypted boot volume;
- AMI name `bakehouse-<git_sha>-<timestamp>`;
- tags **on both the AMI and its snapshots**: `Project=bakehouse`, `Channel=candidate`, `GitSha`, `BaseAmi`, `BuildDate`.

```bash
cd image
packer init .
packer fmt .
packer validate -var git_sha=local .
packer build -var git_sha=local .      # kick this off before lunch!
```

<details><summary>Hint: unique, readable timestamp</summary>

`locals { ts = regex_replace(timestamp(), "[- TZ:]", "") }` and use `local.ts` in `ami_name` and `BuildDate`.
</details>
<details><summary>Hint: the parameter-store data source</summary>

`data "amazon-parameterstore" "al2023" { name = "..." region = var.region }` then `source_ami = data.amazon-parameterstore.al2023.value`.
</details>
<details><summary>Hint: why snapshot tags matter</summary>

A deregistered AMI leaves its EBS snapshots behind. Untagged snapshots are cost you can't attribute and cleanup you can't script. TP5's teardown relies on these tags.
</details>

### TP3.2: Provisioning scripts
Implement `install.sh`, `harden.sh`, `verify.sh` following their header comments. The unit file `files/app.service` is given; read it, because the user-data you write in TP4 has to match what it expects.

Things worth discovering by doing:
- The final hardening step disables sshd, but Packer is *still using SSH* to run the next provisioner. Hence `disable` + `mask` and **not** `--now`. A service that is masked but running keeps its current sessions until the instance shuts down.
- `verify.sh` is the quality gate. Every claim your image makes ("sshd is masked", "auditd enabled", "no pending security updates") is an assertion that fails the build. A failed provisioner means **no AMI is created**.
- AL2023 package for the ECR credential helper is `amazon-ecr-credential-helper`. If your region's repo doesn't carry it, fall back to the release binary from the GitHub project and **verify its checksum**.

<details><summary>Hint: docker + credential helper config</summary>

`dnf install -y docker amazon-ecr-credential-helper`, `systemctl enable docker`, then write `/root/.docker/config.json` containing `{"credsStore":"ecr-login"}` (the unit runs as root).
</details>
<details><summary>Hint: sysctl drop-in</summary>

Put settings in `/etc/sysctl.d/90-bakehouse.conf` and apply with `sysctl --system`. Check your values in `verify.sh` with `sysctl -n <key>`.
</details>

### TP3.3: `image.yml`
Assume `ROLE_IMAGE_FACTORY`, set up Packer, `packer init`, `packer validate`, `packer build -var git_sha=${{ github.sha }}`. Triggers already present: push to `image/**`, manual, monthly schedule.

Expect IAM iteration here: Packer needs a specific set of EC2 permissions, and each missing one shows up as a different `UnauthorizedOperation`. Read the denied action in the error, update `bootstrap/` (it's applied from your laptop, remember), repeat. Then tighten: anything with a wildcard resource that could be scoped by tag (`ec2:CreateTags`, deregistration) should be.

<details><summary>Hint: the packer action</summary>

`hashicorp/setup-packer@main` (pin a version in practice). The runner is arm64 but the builder instance is a separate EC2 machine, so the runner's architecture doesn't matter for the AMI.
</details>

### TP3.4: `promote-image.yml`
Input: AMI id. The workflow must:
1. check that the AMI exists, belongs to you, and has `Project=bakehouse` and `Channel=candidate`. **Refuse anything else**;
2. set `Channel=approved` (on the AMI **and** its snapshots);
3. keep the 2 newest `approved` images; **deprecate** older ones with `ec2 enable-image-deprecation`.

<details><summary>Hint: deprecation</summary>

`aws ec2 enable-image-deprecation --image-id ami-… --deprecate-at <ISO8601 UTC>`. The API refuses dates in the past: use "now + a few minutes". Deprecated images disappear from `describe-images` unless `--include-deprecated`, and the Terraform `aws_ami` data source ignores them by default. That's the effect we want for dev's lookup.
</details>

## Break it
1. **A lying image.** Comment out the `mask sshd` step in `harden.sh`, push. Does the build fail? Where? Is an AMI created? (`aws ec2 describe-images --owners self`.)
2. **A promotion that must be refused.** Run `promote-image` with the id of an AMI that isn't yours (e.g. the public base AMI) or one already `approved`. Read how it refuses.
3. **No door.** Launch a test instance from your candidate in the console/CLI (or wait for TP4). Try `ssh` (no listener) and `aws ssm start-session --target <id>` (works). Which of those leaves an audit trail?

## Checkpoint
```bash
aws ec2 describe-images --owners self --filters Name=tag:Project,Values=bakehouse Name=tag:Channel,Values=approved \
  --query 'Images[].[ImageId,Name,Tags[?Key==`GitSha`]|[0].Value,Tags[?Key==`BaseAmi`]|[0].Value]' --output table
```
You have ≥ 1 approved AMI with a traceable git SHA and base AMI. Note its id.

## Review questions
1. A critical OpenSSL CVE is announced on a Tuesday. What exactly do you do, step by step, and which of those steps involve a human on a server?
2. Why is user-data restricted to "last-mile config only"? What goes wrong if user-data installs Docker at boot?
3. What's the risk of a base AMI looked up as "latest" at build time, and how do the tags mitigate it?
4. `verify.sh` passes but the image is broken at runtime (e.g. wrong port in the unit file). What's missing from your factory? (You'll hit this exact case in TP5.)
5. Why deprecate instead of deregister old AMIs?

## Going further (cut for time)
- **Ansible** instead of shell: idempotent, role-based, testable; the real-world default.
- **goss/InSpec** to test the *booted* image instead of grepping files; **Amazon Inspector** or `trivy rootfs` on the image.
- Packer over **SSM** (`ssh_interface = "session_manager"`): no inbound port at all during the build.
- Multi-region copy and sharing across accounts; AMI signing/attestation.
- Automatic trigger: base AMI changed upstream → rebuild.
