# Route53 (and other "global" AWS services) is region-agnostic, but root.hcl still
# requires a region for the state bucket name and provider. We pin to sa-east-1 so
# global modules share the same state bucket as the regional sa-east-1 stacks.
locals {
  region = "sa-east-1"
}