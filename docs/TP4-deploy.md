# TP4: Deploy (16:00–18:00)

## Objectives
- Assemble everything: the **golden AMI** (TP3) + the **promoted image digest** (TP2) + the **Terraform pipeline** (TP1).
- Build `modules/service`: ALB + Auto Scaling Group + launch template + least-privilege instance role.
- Roll out a change with an **instance refresh** and prove it worked with an automated **smoke test**.
- Understand the pinning strategy: dev *follows*, prod *pins*.

Work in `modules/service/`, `envs/dev/`, `envs/prod/`, `.github/workflows/terraform.yml`.

## Concepts (≈10 min)

**Two inputs define a deployment.** Everything that runs is described by two values: `ami_id` (the OS layer) and `app_image_digest` (the app layer). Both live in git, in `envs/<env>/versions.auto.tfvars`. *Deploying is merging a PR that changes one of them. Rolling back is `git revert`.* There is no other way to change what runs, and so there is always an audit trail.

**Follow vs pin.**
- **dev follows**: `ami_id = null` → a data source finds the newest `approved` AMI. Fast feedback, but the plan can change without any commit (drift by design). It needs a trigger, e.g. manual dispatch or a schedule.
- **prod pins**: `ami_id = "ami-…"` in git. Deterministic: the plan today equals the plan tomorrow. Promotion to prod = a reviewed PR copying the exact values that ran in dev.

**Launch template + instance refresh.** The launch template describes *what* to boot (AMI, type, user-data, role). The ASG describes *how many* and *where*. Changing the template creates a new version; with `launch_template { version = latest_version }` the ASG notices, and an **instance refresh** replaces instances gradually: bring up a new one, wait until it's healthy, then retire the old one. Settings that make this safe for a single-instance service: `min_healthy_percentage = 100` (never drop capacity) and `max_healthy_percentage = 200` (allowed to surge to double during the swap). That surge needs room: the ASG's `max_size` must be at least `2 × desired`.

**What rollback does and doesn't do.** If the new instance never becomes healthy, the refresh keeps terminating and relaunching it (the old instance keeps serving) and gives up after about an hour. `auto_rollback` exists, but when Terraform drives the change it saves the new launch-template version *before* starting the refresh, so "roll back to the previous configuration" likely rolls back to nothing useful. Don't treat it as your safety net: the safety net is the smoke test plus `git revert`.

**Health, as seen by who?** EC2 status checks only say the VM is up. The **ELB health check** (`/health`) says the *application* answers. Set the ASG's `health_check_type = "ELB"` so a VM with a broken app counts as unhealthy, and never receives traffic or replaces a healthy one.

**"terraform apply succeeded" ≠ "deployment succeeded."** Terraform returns as soon as the refresh has been *started* (it only waits for capacity when creating the ASG, e.g. `min_elb_capacity`). The pipeline must check the outcome itself. That is the smoke test.

**No SSH.** The instance has no key pair, no port 22, no sshd. Shell access is Session Manager: authenticated by IAM, logged by CloudTrail.

## Exercises

### TP4.1: `modules/service`
Implement the module following the long TODO comment in `main.tf`. Contract (`variables.tf`/`outputs.tf`) is fixed.

Key requirements:
- **Instance SG**: inbound 80 **from the ALB's SG only**. No port 22. Write SG rules **inline** (`ingress {}`/`egress {}`): TP5's drift drill needs it (see the hint in `main.tf`).
- **IMDSv2 required**, EBS encrypted, no key pair.
- **Instance role**: `AmazonSSMManagedInstanceCore` + ECR read scoped to `var.ecr_repository_arns` (`ecr:GetAuthorizationToken` can only be `"*"`).
- **user-data = last-mile only**: write `/etc/bakehouse/app.env` (`APP_IMAGE=...`, `APP_ENV=...`) and restart `app.service`. Nothing is installed at boot.
- ASG: `health_check_type = "ELB"`, `max_size = 2 × desired`, `instance_refresh` (100/200, warm-up ≥ your real time-to-healthy, e.g. 120 s), target group health check on `/health`. Set `min_elb_capacity` so that a broken *first* deployment fails the apply.

<details><summary>Hint: why the app can't read instance metadata</summary>

The app runs inside a Docker container. With IMDSv2 the response to the token request has a hop limit of 1 by default, and a container adds one network hop. `GET /` will show `ami_id: "unknown"` until you set `http_put_response_hop_limit = 2` on the launch template's `metadata_options`. Trade-off to discuss: it also lets *any* container on the host reach the metadata service.
</details>
<details><summary>Hint: refresh triggers</summary>

In the `launch_template` block of the ASG use `version = aws_launch_template.this.latest_version`. Without it the ASG stays on `$Default` and never refreshes.
</details>
<details><summary>Hint: user_data encoding</summary>

Launch templates want base64: `user_data = base64encode(templatefile("${path.module}/user-data.sh.tftpl", {...}))`. Changing user-data also creates a new template version, which is also a rollout.
</details>
<details><summary>Hint: trivy will complain, rightly</summary>

A public ALB on port 80 and the egress you need without a NAT trip `trivy config`. The real findings are `AVD-AWS-0053` (internet-facing load balancer), `AVD-AWS-0054` (HTTP listener) and `AVD-AWS-0104` (egress to `0.0.0.0/0`). (`AVD-AWS-0107` is the SSH-from-the-internet rule from TP1's break-it; it does not fire for port 80.) Suppress what you accept **in code, with a justification**: `#trivy:ignore:AVD-AWS-0054` plus a comment saying *why*. An exception in code is reviewable; an unreviewed checkbox in a UI isn't. For the public IPs, set `associate_public_ip_address` on the launch template's `network_interfaces`: it isn't flagged, whereas `map_public_ip_on_launch` on the subnet is (`AVD-AWS-0164`).
</details>

### TP4.2: Wire the environments
Fill in `envs/dev/main.tf` and `envs/prod/main.tf` per their TODO comments. Then set the versions:

```hcl
# envs/dev/versions.auto.tfvars
app_image_digest = "sha256:<digest you promoted in TP2>"

# envs/prod/versions.auto.tfvars
ami_id           = "ami-<approved AMI from TP3>"
app_image_digest = "sha256:<same digest>"
```

Differences you must encode: dev's instance role may pull `candidates` + `releases`; **prod's may pull `releases` only**. Prod must refuse to plan without a pinned AMI (a `validation` or `precondition`).

Open a PR. Read the dev plan comment carefully before merging: what will be created? Merge, approve `prod`, and wait.

### TP4.3: Smoke test in the pipeline
Add a job after each `apply-*` that:
1. reads `alb_dns_name` and `asg_name` outputs;
2. waits (with a **timeout**) until the latest instance refresh is `Successful`: `aws autoscaling describe-instance-refreshes --auto-scaling-group-name … --max-records 1`;
3. `curl`s `http://<alb>/` and asserts that `env` and `ami_id` are the **expected** values (the ones in git or the lookup), and that `app_version` is not the default `dev`/`unknown` (the version is a build argument; it appears nowhere in git, only the digest does);
4. fails the workflow, loudly, otherwise.

Use `ROLE_TF_PLAN` (read-only is enough: an assertion shouldn't need write access). **The smoke-test job must not declare an `environment:`**: a job with an environment presents only the environment form of the OIDC `sub`, which `tf-plan` doesn't trust. Pass `alb_dns_name`, `asg_name`, `ami_id` from the apply job as job `outputs` rather than re-reading state.

### TP4.4: Ship a change end to end
Do the full loop once, as you would at work:
1. Change the app (e.g. add a field to the JSON in `app/main.go`) → PR → merge → `app.yml` builds a **candidate**.
2. `promote-app` with the new digest.
3. PR: bump `app_image_digest` in `envs/dev/versions.auto.tfvars`. Merge. Watch the refresh in the console (EC2 → Auto Scaling groups → Instance refresh). Smoke test goes green.
4. PR: copy the same digest into `envs/prod/versions.auto.tfvars`. Merge, approve.
5. `curl` both ALBs; the JSON shows the new version. Note the `instance_id` changed, which is the refresh, visible from outside.

> Short on time? Steps 1–3 are the core; steps 4–5 repeat the same mechanism for prod and can run while you start TP5 (`curl` in a loop is a great way to watch Drill 2 later).

## Break it
1. **Shell without SSH.** `aws ssm start-session --target <instance-id>`. Look around (`systemctl status app`, `docker ps`, `sudo cat /etc/bakehouse/app.env`). Then try `nc -zv <public-ip> 22`. Open ports: none.
2. **Prod can't pull candidates.** On a prod instance (via SSM): `docker pull <candidates-repo>@<digest>`. Read the error. That's the IAM scope doing its job.
3. **Tag instead of digest.** Set `app_image` to `…app-releases:latest` in a PR. What stops you? (Your `validation` in `variables.tf`.)

## Checkpoint
```bash
curl -s http://$(terraform -chdir=envs/prod output -raw alb_dns_name)/ | jq .
# { "app_version": "...", "git_sha": "...", "env": "prod", "ami_id": "ami-…", "instance_id": "i-…" }
```
- `env` is `prod` and `ami_id` equals the value pinned in git.
- The pipeline run for prod shows: apply ✅ → smoke test ✅.
- No security group in the account has port 22 open.

## Review questions
1. Why does the ALB health check path matter more than EC2 status checks?
2. Dev uses a data source for the AMI. Name one advantage and one risk compared with a pinned id.
3. `min_healthy_percentage = 100` on a one-instance ASG: what must be true for a refresh to ever make progress? (Two settings, one on the refresh and one on the ASG.)
4. The apply succeeded, the new instances are failing health checks. Who finds out, and when? What would you add to find out sooner? (Hint: refresh `alarm_specification` and CloudWatch alarms on `UnHealthyHostCount`.)
5. You need to patch prod's OS tonight. List the exact sequence from CVE announcement to prod, including approvals.

## Going further (cut for time)
- Blue/green or canary behind the ALB with weighted target groups.
- HTTPS (ACM certificate, 443 listener, redirect), WAF.
- Private subnets + VPC endpoints (ECR, SSM, S3) instead of public IPs: the cost-vs-security trade you declined today.
- Auto scaling policies; `desired_capacity` ownership (`ignore_changes`).
- Automatic PR creation for version bumps (Renovate-style) and automatic promotion dev → prod after a soak period.
