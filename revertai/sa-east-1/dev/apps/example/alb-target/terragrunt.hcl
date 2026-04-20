terraform {
  source = "${get_parent_terragrunt_dir()}/modules/alb-target"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  environment      = local.environment_vars.locals.environment
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vpc" {
  config_path = "../../../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    vpc_id = "vpc-00000000"
  }
}

dependency "alb" {
  config_path = "../../../alb"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    listeners = {
      http = { arn = "arn:aws:elasticloadbalancing:sa-east-1:000000000000:listener/app/dummy/00000000/00000000" }
    }
  }
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
  name                   = "${local.environment}-example"
  vpc_id                 = dependency.vpc.outputs.vpc_id
  container_port         = 80
  alb_listener_arn       = dependency.alb.outputs.listeners["http"].arn
  host                   = "example.dev.internal"
  listener_rule_priority = 100
  health_check_path      = "/"

  tags = dependency.tags.outputs.tags
}
