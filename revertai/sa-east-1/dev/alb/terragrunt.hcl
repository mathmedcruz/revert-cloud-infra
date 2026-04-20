terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-alb.git//.?ref=v9.11.0"
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

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    vpc_id         = "vpc-00000000"
    public_subnets = ["subnet-00000000", "subnet-00000001", "subnet-00000002"]
  }
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
  name    = "${local.app_name}-${local.environment}"
  vpc_id  = dependency.vpc.outputs.vpc_id
  subnets = dependency.vpc.outputs.public_subnets

  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTP from anywhere"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  # Default action = fixed 404. Each app registers its own listener rule
  # (created in modules/app/) matched by host_header to forward to its target group.
  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      fixed_response = {
        content_type = "text/plain"
        message_body = "404 Not Found"
        status_code  = "404"
      }
    }
  }

  # No target groups created here. Each app in apps/<name>/ creates its own TG
  # and listener rule via the local module (modules/app/).
  target_groups = {}

  tags = dependency.tags.outputs.tags
}
