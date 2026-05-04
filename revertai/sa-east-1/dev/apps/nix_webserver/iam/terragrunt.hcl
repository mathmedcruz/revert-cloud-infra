terraform {
  source = "${get_parent_terragrunt_dir()}/modules/iam-shared-roles"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region
  account_id  = local.account_vars.locals.account_number
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "tags" {
  config_path = "../../../tags"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    tags = {}
  }
}

inputs = {
  # 'dev-nix' → 'dev-nix-ecs-exec' / 'dev-nix-ecs-task'.
  name_prefix = "${local.environment}-nix"
  account_id  = local.account_id
  region      = local.region
  tags        = dependency.tags.outputs.tags
}
