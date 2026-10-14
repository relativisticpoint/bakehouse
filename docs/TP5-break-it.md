# TP5: Break it, and tear it down (17:00–18:00)

## Objectives
A pipeline is production grade when its **failure paths** work. In this TP you break the platform four ways on purpose and watch each safeguard (or its absence) do its job. Then you shut everything down, and the money stops.

Rules for the hour: before each drill, **write down what you expect to happen**. The learning is the difference between expectation and reality.

## Drill 1: A vulnerable artifact (≈10 min)
*Safeguard under test: the trivy gate in `app.yml`.*

1. On a branch, make the app build with an **old Go toolchain**. The standard library is compiled into the binary, so an old toolchain ships old, vulnerable `net/http` code:
   - in `app/Dockerfile`: `FROM golang:1.26.0 AS build`
   - in `app/go.mod`: `go 1.26`
2. Open a PR. Watch the `app` job: it must fail at the scan step, **before** any push. Confirm nothing new exists in ECR (`aws ecr describe-images --repository-name bakehouse/app-candidates`).
3. Read the findings. Which are fixable? Why does `--ignore-unfixed` exist, and what risk does it accept?
4. Close the PR.

> **Why not just use an old OS base image?** We tried `alpine:3.14`: trivy reports **0 findings**. The distribution is end-of-life, so there is no advisory data to match against, and the scanner reports clean on an image that is anything but. *A clean scan is only as good as the scanner's data.* Know what your scanner can't see (EOL operating systems, unlisted ecosystems) and pair it with a policy that forbids those bases.
>
> The same mechanism works in the other direction: the app on a floating `golang:1.27` tag was clean the day we wrote this course and will not be clean forever. Gates catch decay only if something rebuilds on a schedule (Renovate/Dependabot, and the monthly image rebuild).

*Expected:* red build, zero artifacts. If the gate lets it through, find out why (severity filter? `--exit-code`?) and fix the gate. That's the real exercise.

## Drill 2: A bad AMI reaches dev (≈25 min)
*Safeguards under test: instance refresh with health checks, the smoke test, and rollback by `git revert`.*

The base `app.service` runs the container with `-p 80:8080`. `verify.sh` never checks that the service actually serves traffic. Exploit that gap:

1. PR: in `image/files/app.service` change `-p 80:8080` to `-p 80:9090`. Merge. `image-factory` bakes a new **candidate**; `verify.sh` is green (it only checks the unit is enabled).
2. Run `promote-image` for the new AMI id → it becomes `approved`.
3. Trigger the Terraform workflow manually (`workflow_dispatch`): dev follows `approved`, so the plan now wants to replace the instances. Watch what happens in the console:
   - Does the old instance keep serving traffic while the new one boots?
   - What do the target group's health checks say about the new instance?
   - What does the instance refresh status do over the next minutes? Does automatic rollback fire? Look at `aws autoscaling describe-instance-refreshes`.
4. Meanwhile `curl` the dev ALB in a loop (`while sleep 2; do curl -s -o /dev/null -w '%{http_code}\n' http://<dev-alb>/; done`). **Was there downtime?**
5. What did the pipeline's smoke test do? If it hung or passed wrongly, fix TP4.3 (timeouts, assertions on the *expected* AMI id).
6. **Recover** the way you would in production: revert the `app.service` change in a PR, let a new candidate be baked and approved, re-run the deploy. Also deprecate the bad AMI (`Channel` → `rejected`, deprecate it) so nothing can pick it up again.

> Be careful and write down what you observe rather than what the doc says. Instance-refresh rollback and failure behaviour has several conditions; the point is to learn how *your* configuration behaves.

**Close the gap.** Add one functional check to the factory so this class of bug can't reach `approved`: e.g. in `verify.sh`, parse the `docker run` line in `app.service` and compare its published container port with the `EXPOSE` / the port the app listens on; or boot the candidate once and curl `/health` as a pre-promotion test. Which is better and why?

Then write a short **postmortem** (template below).

## Drill 3: Drift (≈10 min)
*Safeguard under test: nothing, today. That's the lesson.*

1. In the AWS console, edit dev's instance security group: add an inbound rule you invent (say, TCP 8080 from `0.0.0.0/0`).
2. From your laptop, plan `envs/dev` (`terraform init -backend-config="bucket=…"`, then `terraform plan`). Terraform shows the drift and proposes to remove the rule.
3. Question: **when would the pipeline have found out on its own?** (Answer: only at the next unrelated change.) Sketch a scheduled workflow: `terraform plan -detailed-exitcode` (exit code 2 = changes) that opens an issue or alerts. Implement it if you have time, otherwise it's in "Going further".
4. Let the pipeline restore the rule set: trigger a dev apply via `workflow_dispatch`.

## Drill 4: Teardown (≈15 min)
Order matters: things that depend on others go first. Use your admin profile from your laptop (the pipeline roles are deliberately unable to delete everything).

```bash
export AWS_PROFILE=bakehouse
ACCT=$(aws sts get-caller-identity --query Account --output text)

# 1. Environments: prod, then dev
for env in prod dev; do
  (cd envs/$env && terraform init -backend-config="bucket=bakehouse-tfstate-$ACCT" && terraform destroy)
done

# 2. Artifact repositories (delete images first, or make the repos force-deletable;
#    batch-delete-image errors on an empty repo, which is fine, skip it)
aws ecr batch-delete-image --repository-name bakehouse/app-candidates \
  --image-ids "$(aws ecr list-images --repository-name bakehouse/app-candidates --query 'imageIds' --output json)"
aws ecr batch-delete-image --repository-name bakehouse/app-releases \
  --image-ids "$(aws ecr list-images --repository-name bakehouse/app-releases --query 'imageIds' --output json)"
(cd artifacts && terraform init -backend-config="bucket=bakehouse-tfstate-$ACCT" && terraform destroy)

# 3. AMIs and their snapshots (this is why you tagged the snapshots)
for ami in $(aws ec2 describe-images --owners self --filters Name=tag:Project,Values=bakehouse --include-deprecated --query 'Images[].ImageId' --output text); do
  aws ec2 deregister-image --image-id "$ami"
done
for snap in $(aws ec2 describe-snapshots --owner-ids self --filters Name=tag:Project,Values=bakehouse --query 'Snapshots[].SnapshotId' --output text); do
  aws ec2 delete-snapshot --snapshot-id "$snap"
done

# 4. Verify: nothing billable should be left tagged Project=bakehouse
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=bakehouse \
  --query 'ResourceTagMappingList[].ResourceARN' --output text
```

What remains on purpose: the **state bucket** (pennies; `prevent_destroy`), the **IAM roles** and **OIDC provider** (free), your GitHub repo. To rebuild the platform another day, re-run the pipelines.

Finally, **retire the admin key** you created for the day:
```bash
aws iam list-access-keys --user-name bakehouse-admin
aws iam update-access-key --user-name bakehouse-admin --access-key-id <ID> --status Inactive
aws iam delete-access-key --user-name bakehouse-admin --access-key-id <ID>
# optional: delete the user; remove the [bakehouse] profile from ~/.aws/credentials
```
Check **Billing → Bills** tomorrow: expect a couple of dollars at most.

## Postmortem template (for Drill 2)
Keep it blameless and short:

```
Title:            <what broke, in one line>
Impact:           <who/what was affected, for how long, was there downtime?>
Detection:        <how did we find out? how long after the change?>
Timeline (UTC):   <time: event> ...
Root cause:       <the real cause, not "human error". What control was missing?>
What went well:   <which safeguards worked?>
What went wrong:  <which safeguards didn't, or didn't exist?>
Action items:     <owner | action | due | how we'll know it worked>
```

## Final review: the whole platform in your own words
Answer these without looking at the docs, then compare with what you built:
1. Trace a one-line app change from `git push` to a prod instance serving it. Name every artifact, every gate, every identity (role/OIDC subject) involved.
2. Same, for an OS-level security patch.
3. Which three controls would you tighten first to take this to a real company, and why those?
4. Where is the **single source of truth** for "what runs in prod right now"?
5. Which concept from today will you recognise first when you open a real Artifactory instance?

## Going further
- Drift detection on a schedule, with alerting.
- Move prod to its own AWS account; add SCPs.
- Policy-as-code (OPA/conftest on the plan JSON) and cost estimation (Infracost) in PRs.
- Rebuild the whole thing in another region from scratch with the pipelines only, and time it.
