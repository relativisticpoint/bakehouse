plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# TODO(TP4.1): delete this rule override once modules/service uses its variables.
# Until then every declared-but-unused variable is a warning, and tflint exits non-zero on warnings.
rule "terraform_unused_declarations" {
  enabled = false
}
