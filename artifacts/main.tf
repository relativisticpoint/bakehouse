# Artifact repositories (TP2). Shared by all environments, so they live in their own stack.
#
# TODO(TP2.1): two ECR repositories
#   bakehouse/app-candidates   every CI build lands here
#   bakehouse/app-releases     only promoted (verified, signed) digests land here
# Both: image_tag_mutability = "IMMUTABLE", scan_on_push = true, encryption.
# Candidates: lifecycle policy keeping the last 20 images.
# Releases:   lifecycle policy that never expires images referenced by prod (think: why is a
#             retention policy dangerous when you deploy by digest?).
# Then publish the repo names as GitHub variables ECR_CANDIDATES / ECR_RELEASES.
