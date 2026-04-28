terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-route53.git//.?ref=v6.4.0"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  environment = local.environment_vars.locals.environment
  root_domain = local.account_vars.locals.root_domain
  zone_name   = "${local.environment}.${local.root_domain}"

  # AJUSTE: subdomínio público da app. DEVE ser igual ao `app_host` em ../alb-target/terragrunt.hcl
  # senão o ALB não roteia a request (host_header não bate).
  app_subdomain = "python-app"
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
    (local.app_subdomain) = {
      type = "A"
      alias = {
        name                   = dependency.alb.outputs.dns_name
        zone_id                = dependency.alb.outputs.zone_id
        evaluate_target_health = true
      }
    }
  }
}
