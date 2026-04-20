# Automatically load account-level, region-level and environment-level variables.
locals {
  commons_vars     = read_terragrunt_config(find_in_parent_folders("commons.hcl"))
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))

  app_name       = local.commons_vars.locals.app_name
  account_number = local.account_vars.locals.account_number
  region         = local.region_vars.locals.region
}

# Configure Terragrunt to automatically store tfstate files in S3.
# State locking uses S3 native lockfiles (requires Terraform >= 1.10 and bucket versioning).
# The backend tf file is dynamically generated for each module.
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }

  config = {
    encrypt      = true
    bucket       = format("%s-%s-terraform-remote-state", local.account_number, local.region)
    key          = format("%s/%s/terraform.tfstate", local.app_name, path_relative_to_include())
    use_lockfile = true
    region       = local.region
  }
}

# Generate an AWS provider block.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.region}"
}
EOF
}

terraform {
  # Force Terraform to keep trying to acquire a lock for up to 20 minutes
  # if someone else already has the lock.
  extra_arguments "retry_lock" {
    commands = get_terraform_commands_that_need_locking()

    arguments = [
      "-lock-timeout=20m"
    ]
  }

  # Force Terraform to keep trying to acquire a lock for up to 20 minutes
  # if someone else already has the lock.
  extra_arguments "auto_approve" {
    commands = [
      "apply"
    ]

    arguments = [
      "-auto-approve"
    ]
  }

  extra_arguments "fix-log-output" {
    commands = get_terraform_commands_that_need_vars()

    arguments = [
      "-no-color"
    ]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL PARAMETERS
# These variables apply to all configurations in this subfolder. These are automatically merged into the child
# `terragrunt.hcl` config via the include block.
# ---------------------------------------------------------------------------------------------------------------------

# Configure root level variables that all resources can inherit. This is especially helpful with multi-account configs
# where terraform_remote_state data sources are placed directly into the modules.
inputs = merge(
  local.commons_vars.locals,
  local.account_vars.locals,
  local.region_vars.locals,
  local.environment_vars.locals
)
