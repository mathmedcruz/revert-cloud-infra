terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/cluster?ref=v5.12.0"
}

locals {
  commons_vars     = read_terragrunt_config(find_in_parent_folders("commons.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))

  app_name    = local.commons_vars.locals.app_name
  environment = local.environment_vars.locals.environment
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "tags" {
  config_path = "../tags"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    tags = {}
  }
}

inputs = {
  cluster_name = "${local.app_name}-${local.environment}"

  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 100
      }
    }
  }

  tags = dependency.tags.outputs.tags
}
