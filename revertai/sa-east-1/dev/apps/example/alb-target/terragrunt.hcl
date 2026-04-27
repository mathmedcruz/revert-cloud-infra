terraform {
  source = "${get_parent_terragrunt_dir()}/modules/alb-target"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  environment = local.environment_vars.locals.environment
  root_domain = local.account_vars.locals.root_domain

  # AJUSTE: hostname público da app. O subdomínio (parte antes do primeiro ".") DEVE
  # ser igual a `app_subdomain` em ../dns/terragrunt.hcl.
  app_host = "exemplo.${local.environment}.${local.root_domain}"
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
  # AJUSTE: nome do target group (limite de 32 chars na AWS, prefixo "tg-" é adicionado pelo módulo).
  name = "${local.environment}-example"

  vpc_id           = dependency.vpc.outputs.vpc_id
  container_port   = 80
  alb_listener_arn = dependency.alb.outputs.listeners["http"].arn
  host             = local.app_host

  # AJUSTE: prioridade da regra no listener do ALB. DEVE ser única entre todas as apps.
  # Padrão: incremente de 10 em 10 ao adicionar nova app (100, 110, 120, ...).
  listener_rule_priority = 100

  # AJUSTE: path do health check do target group.
  health_check_path = "/"

  tags = dependency.tags.outputs.tags
}
