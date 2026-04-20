terraform {
  source = "${get_parent_terragrunt_dir()}/modules/app"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vpc" {
  config_path = "../../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    vpc_id          = "vpc-00000000"
    private_subnets = ["subnet-00000000", "subnet-00000001", "subnet-00000002"]
  }
}

dependency "alb" {
  config_path = "../../alb"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    listeners = {
      http = { arn = "arn:aws:elasticloadbalancing:sa-east-1:000000000000:listener/app/dummy/00000000/00000000" }
    }
    security_group_id = "sg-00000000"
  }
}

dependency "ecs_cluster" {
  config_path = "../../ecs-cluster"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    arn = "arn:aws:ecs:sa-east-1:000000000000:cluster/dummy"
  }
}

dependency "tags" {
  config_path = "../../tags"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    tags = {}
  }
}

inputs = {
  name        = "example"
  environment = local.environment
  region      = local.region

  cpu           = 256
  memory        = 512
  desired_count = 1

  expose_via_alb         = true
  host                   = "example.dev.internal"
  container_port         = 80
  listener_rule_priority = 100
  health_check_path      = "/"

  vpc_id                = dependency.vpc.outputs.vpc_id
  private_subnet_ids    = dependency.vpc.outputs.private_subnets
  ecs_cluster_arn       = dependency.ecs_cluster.outputs.arn
  alb_listener_arn      = dependency.alb.outputs.listeners["http"].arn
  alb_security_group_id = dependency.alb.outputs.security_group_id

  tags = dependency.tags.outputs.tags
}
