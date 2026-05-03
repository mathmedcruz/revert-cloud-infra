terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-route53.git//.?ref=v6.4.0"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  environment = local.environment_vars.locals.environment
  root_domain = local.account_vars.locals.root_domain
  zone_name   = "${local.environment}.${local.root_domain}"

  # Multi-tenant: 2 records no mesmo ALB.
  # - api → apex (rotas shared)
  # - *.api → wildcard (1 record cobre todos os tenants)
  # Subdomínios DEVEM casar com `host` em ../alb-target/terragrunt.hcl.
  app_apex_subdomain     = "api"
  app_wildcard_subdomain = "*.api"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../../../../../_global/route53/dev-revertai-com-br/route53"]
}

dependency "alb" {
  config_path = "../../../alb"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    dns_name = "dummy.elb.amazonaws.com"
    zone_id  = "Z00000000000000000"
  }
}

inputs = {
  create_zone = false
  name        = local.zone_name

  records = {
    (local.app_apex_subdomain) = {
      type = "A"
      alias = {
        name                   = dependency.alb.outputs.dns_name
        zone_id                = dependency.alb.outputs.zone_id
        evaluate_target_health = true
      }
    }
    (local.app_wildcard_subdomain) = {
      type = "A"
      alias = {
        name                   = dependency.alb.outputs.dns_name
        zone_id                = dependency.alb.outputs.zone_id
        evaluate_target_health = true
      }
    }
  }
}
