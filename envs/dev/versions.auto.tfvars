# What is deployed in dev. Changing a value here (via PR) IS the deployment.
# ami_id is omitted in dev: Terraform looks up the latest approved AMI.

# PLACEHOLDER so that `plan` works in TP1-TP3 (it passes the validation but points at nothing).
# TODO(TP4.2): replace with the digest you promoted in TP2.
app_image_digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
