terraform {
  source = "${get_parent_terragrunt_dir()}/modules/alb-target"
}

# Multi-tenant: a request chega como `<tenant>.api.dev.revertai.com.br`.
# - Apex (api.dev...) atende /api/health/, /api/auth/login/, etc. (rotas do schema public).
# - Wildcard (*.api.dev...) atende rotas dos schemas tenant. Resolução é feita no
#   middleware PublicDomainMiddleware do Django via Domain.objects.get(domain=host).
#
# Atenção: o cert ACM atual do listener é `*.dev.revertai.com.br` (1 nível),
# que NÃO cobre `<tenant>.api.dev.revertai.com.br` (2 níveis). Pra TLS funcionar
# pra cada tenant, é necessário emitir cert adicional `*.api.dev.revertai.com.br`
# e anexar ao listener via aws_lb_listener_certificate (dificuldade #1 do plan).

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  environment = local.environment_vars.locals.environment
  root_domain = local.account_vars.locals.root_domain

  # AJUSTE: hostnames públicos da app. Subdomínios DEVEM bater com os records em ../dns/.
  app_apex     = "api.${local.environment}.${local.root_domain}"
  app_wildcard = "*.api.${local.environment}.${local.root_domain}"
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
  mock_outputs_merge_strategy_with_state  = "deep_map_only"
  mock_outputs = {
    listeners = {
      https = { arn = "arn:aws:elasticloadbalancing:sa-east-1:000000000000:listener/app/dummy/00000000/00000000" }
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
  # `nix-web` (com hyphen) — `_` não é permitido em target group name.
  # Tamanho final: tg-dev-nix-web = 14 chars (limite 32).
  name = "${local.environment}-nix-web"

  vpc_id           = dependency.vpc.outputs.vpc_id
  container_port   = 8000
  alb_listener_arn = dependency.alb.outputs.listeners["https"].arn

  # 2 hosts no mesmo target group: apex + wildcard tenant.
  host = [local.app_apex, local.app_wildcard]

  # Próximo slot após python_app (110). Próxima app: 130.
  listener_rule_priority = 120

  # Endpoint do Django: HealthCheckViewSet em common.endpoint.health_check
  health_check_path = "/api/health/"

  tags = dependency.tags.outputs.tags
}
