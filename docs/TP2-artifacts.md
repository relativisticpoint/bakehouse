# TP2: Artifacts & supply chain (11:15–13:00)

## Objectives
- Explain what an **artifact repository** is for and map the Artifactory vocabulary onto ECR.
- Build the app image once, then **scan → push → attest → sign** it in CI.
- **Promote** an image from `candidates` to `releases` by digest, without rebuilding, only if its signature verifies.

Work in `artifacts/`, `.github/workflows/app.yml`, `.github/workflows/promote-app.yml`.

## Concepts (≈15 min)

**Why an artifact repository?** Source code is not what you run. You run a *build output*. If dev and prod each build from source, you are shipping two different things and testing only one. The rule: **build once, deploy many**. The artifact repository is the single place where build outputs live, with a version, a provenance trail and rules about who can add or change things.

**Artifactory vocabulary ↔ what we use**

| JFrog Artifactory | Idea | Bakehouse today |
|---|---|---|
| Local repository | Stores your own artifacts | ECR private repository |
| Remote repository | Caching proxy of an upstream (Docker Hub, npm…) | ECR pull-through cache (not built today) |
| Virtual repository | One URL that aggregates several repos | No direct ECR equivalent |
| Xray | Vulnerability / license scanning | trivy in CI + ECR scan-on-push |
| Build promotion | Move a build between "dev → staging → release" repos | `promote-app` workflow: candidates → releases |
| Properties / metadata | Labels on artifacts | Tags, signatures, attestations |
| Retention / cleanup | Delete old artifacts | ECR lifecycle policies |

**Tags vs digests.** A *tag* (`app:1.2.0`, `app:latest`) is a movable label. A *digest* (`sha256:9f…`) is the hash of the image manifest: it identifies exact bytes forever. Deploy by digest. Immutable tags reduce the risk; digests remove it.

**Supply-chain artifacts attached to an image**
- **SBOM** (software bill of materials): the list of everything inside, so you can answer "are we affected by CVE-X?" in seconds. Tool: `syft`.
- **Vulnerability gate**: fail the build on fixable HIGH/CRITICAL findings. Tool: `trivy`.
- **Signature**: proof that *this digest* was produced by *this pipeline*. Tool: `cosign`.

**Keyless signing (Sigstore).** No private key to store or leak: the workflow's OIDC token is exchanged for a short-lived certificate whose identity is the workflow itself (e.g. `https://github.com/<owner>/bakehouse/.github/workflows/app.yml@refs/heads/main`). The signature is logged in a public transparency log (Rekor). Verification checks **who** signed, not "some key".

**Promotion is a controlled copy, not a rebuild.** `candidates` receives every CI build. Only a digest that passes verification gets copied into `releases`, and production can only pull from `releases`. Same bytes, more trust.

## Exercises

### TP2.1: `artifacts/` stack (Terraform, through the pipeline)
Create two ECR repositories `bakehouse/app-candidates` and `bakehouse/app-releases`: `IMMUTABLE` tags, scan on push, encryption. Add lifecycle policies (candidates: keep the last 20 images; releases: keep more, and think before you let it expire anything). Output both repository URLs.

Add the `artifacts` stack to `terraform.yml`: include it in the plan matrix and apply it before `apply-dev`. The apply role only trusts `environment:dev` and `environment:prod`, so the artifacts apply job **borrows the `dev` environment** (the alternative is a third trusted environment: more setup, same idea). Also generate its lock file for the three platforms.

Then publish the repo names for later workflows:
```bash
gh variable set ECR_CANDIDATES --body bakehouse/app-candidates
gh variable set ECR_RELEASES   --body bakehouse/app-releases
```

<details><summary>Hint</summary>

`aws_ecr_repository` (`image_tag_mutability = "IMMUTABLE"`, `image_scanning_configuration { scan_on_push = true }`), `aws_ecr_lifecycle_policy` with a `countType = "imageCountMoreThan"` rule. Careful: ECR counts every image, and cosign adds extra artifacts (`sha256-….sig`, `.att`) per build, so "keep the last 20" keeps roughly 7 builds unless the `sha256-` tags get their own rule. For `releases`, the count rule is exactly the policy review question 4 warns about: only expire untagged leftovers.
</details>

### TP2.2: `app.yml`: build, gate, push, attest, sign
On `pull_request`: build the image (arm64) and scan it. **No push, no AWS credentials.** On `push` to main: all of that, then publish.

Order for the main-branch path (the order is the lesson. Decide what must happen *before* the push):
1. build the image locally in the runner (`docker buildx build --load`, build args `VERSION`, `GIT_SHA`);
2. **trivy gate**: `--exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed`;
3. assume `ROLE_ARTIFACTS`, log in to ECR, push as `:<git-sha>`;
4. get the **digest** of what was pushed;
5. SBOM with `syft`, attach it as an attestation with `cosign attest`;
6. `cosign sign` the image **by digest**.

Print the digest in the job summary so that TP2.3 has something to promote.

<details><summary>Hint: ECR login and digest</summary>

`aws-actions/amazon-ecr-login@v2` outputs `registry`. To get the digest after the push, `aws ecr describe-images --image-ids imageTag=<sha>` or `crane digest <repo>:<sha>` are more robust than `docker inspect` (and also serve the re-run case in Break it 1).
</details>
<details><summary>Hint: cosign</summary>

`sigstore/cosign-installer@v3` with an explicit `cosign-release:` (the installer's default lags, and the TP assumes cosign **2.x**: `cosign download attestation`, `.sig` tags). Keyless means no `--key`: just `cosign sign --yes <repo>@<digest>`, with `id-token: write`. SBOM: `syft <image> -o spdx-json=sbom.spdx.json`, then `cosign attest --yes --type spdxjson --predicate sbom.spdx.json <repo>@<digest>`.
</details>
<details><summary>Hint: sign by digest, never by tag</summary>

Signing `repo:sha-tag` makes cosign resolve the tag at that moment and warn you for good reason: tags move. Always pass `repo@sha256:…`.
</details>

### TP2.3: `promote-app.yml`
Input: a digest. Steps:
1. assume `ROLE_ARTIFACTS`;
2. `cosign verify` **and** `cosign verify-attestation` (the SBOM) the digest in `candidates`, pinning the **certificate identity** to this repo's `app.yml` on `main` and the **OIDC issuer** to `https://token.actions.githubusercontent.com`;
3. copy **the image** to `releases` by digest with `crane copy` (skip if the tag already exists);
4. **assert** the digest in `releases` equals the input;
5. in `releases`, create a **fresh** signature (and re-attach the verified SBOM) under the *promote* workflow's identity. Result: `candidates` holds the "built by app.yml" signature, `releases` holds "promoted by promote-app.yml", and the first was checked in step 2.

> **Why not copy the signatures too, or sign twice?** cosign stores a signature under a tag derived from the digest (`sha256-<hex>.sig`). `cosign copy` writes that tag into `releases`, and a second signer would then *rewrite* it, which an `IMMUTABLE` repository refuses. Guard each cosign step with an "already there?" check so re-runs don't fail either. (Newer cosign stores signatures as OCI 1.1 referrers instead, which avoids this; know which major you pinned.)

<details><summary>Hint: verify</summary>

`cosign verify --certificate-identity "https://github.com/${{ github.repository }}/.github/workflows/app.yml@refs/heads/main" --certificate-oidc-issuer https://token.actions.githubusercontent.com "$REPO@$DIGEST"`
</details>
<details><summary>Hint: copy</summary>

`crane copy "$SRC@$DIGEST" "$DST:promoted-${DIGEST:7:12}"` copies the image preserving the digest (releases is immutable, so derive the tag from the digest and copy only if it's absent). Check with `crane digest "$DST:promoted-…"`; `crane digest` of the tag must equal the input.
</details>

## Break it
1. **Immutability.** Re-run the `app.yml` push job for the same commit. It tries to push the same tag, and the push fails. A rebuild is never byte-identical (BuildKit embeds a creation timestamp), so the tag would point at a *different* digest. Decide: fail, or skip. A skip must **reuse the existing digest**, never push a new one; real pipelines check first (`aws ecr describe-images --image-ids imageTag=<sha>`).
2. **The gate.** Build the app locally with an old toolchain (`FROM golang:1.26.0` in the Dockerfile's build stage, `go 1.26` in `go.mod`) and run the exact gate command: `trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 <image>`. Read what it reports and what exit code it returns. Then revert your local change. (You'll run this through the pipeline in TP5.)
3. **Unsigned digest.** From your laptop (admin profile), `docker push` a random image to `app-candidates` as tag `manual`. Take its digest and run `promote-app` with it. `cosign verify` must refuse. This is the entire point: *the repository accepting an image is not the same as the image being trusted*.
4. **Wrong identity.** Verify a real signed digest but with `--certificate-identity` pointing at a different workflow filename. Read the error.

## Checkpoint
```bash
# same bytes in both repositories
crane digest <acct>.dkr.ecr.eu-west-3.amazonaws.com/bakehouse/app-candidates:<git-sha>
crane digest <acct>.dkr.ecr.eu-west-3.amazonaws.com/bakehouse/app-releases:<tag>     # identical

# signature checks out from your laptop
aws ecr get-login-password --region eu-west-3 | docker login --username AWS --password-stdin <acct>.dkr.ecr.eu-west-3.amazonaws.com
# the exact form the pipeline uses (stricter than a regexp). A release is signed by promote-app.yml:
cosign verify --certificate-identity "https://github.com/<owner>/bakehouse/.github/workflows/promote-app.yml@refs/heads/main" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com <releases-repo>@<digest> | jq .

# SBOM downloadable
cosign download attestation <candidates-repo>@<digest> | jq -r .payload | base64 -d | jq '.predicate.packages | length'
```

Write down the **digest** you promoted. You need it in TP4.

## Review questions
1. Why is "we always deploy `latest`" a production risk even if tags are immutable elsewhere?
2. What does `cosign verify` prove? What does it *not* prove?
3. Why is the trivy gate before the push? What is lost if it runs after?
4. The `releases` lifecycle policy expires old images. Production runs by digest an image that's now 30 versions old. What happens at the next scale-out event?
5. Who can assume `ROLE_ARTIFACTS`, and can a PR from a branch do it? Why does the PR build job not need it?

## Going further (cut for time)
- ECR pull-through cache for Docker Hub (the "remote repository" idea) and a policy that all base images come from your cache.
- SLSA provenance attestations (`actions/attest-build-provenance`) and admission-style checks on the instance (verify before `docker run`).
- A real Artifactory: virtual repositories, Xray policies, Build-Info. The concepts above transfer one-to-one.
- Replace "copy on dispatch" with automatic promotion once smoke tests pass in dev.
