# Cloud Map HTTP namespace usado por ECS Service Connect.
# Cria UM namespace `rvt-${env}.local` (ex.: rvt-dev.local). Services do
# nix_webserver com `service_connect_configuration` resolvem aliases sob
# esse namespace (ex.: evolution-api.rvt-dev.local:8080).
#
# Por que HTTP namespace (e não Private DNS):
#   - Service Connect aceita os dois.
#   - HTTP namespace é mais barato (~$0/mês vs $0.50/mês private DNS).
#   - Nome do namespace ainda funciona como sufixo DNS (ECS Service Connect
#     cria entradas DNS no resolver do envoy sidecar — não usa Route53).
#   - Se algum dia precisar resolver fora do ECS (ex.: Lambda fora da VPC),
#     trocar pra `aws_service_discovery_private_dns_namespace`.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Namespace é um recurso AWS único por VPC; não precisa de módulo dedicado.
# Inline aqui pra evitar sobrecarga de criar diretório `modules/cloudmap/`
# pra um único `aws_service_discovery_http_namespace`.
generate "main" {
  path      = "main.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.5"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = ">= 5.0"
        }
      }
    }

    variable "namespace_name" {
      type        = string
      description = "Nome do HTTP namespace (ex.: rvt-dev.local). É o sufixo DNS dos aliases."
    }

    variable "tags" {
      type    = map(string)
      default = {}
    }

    resource "aws_service_discovery_http_namespace" "this" {
      name        = var.namespace_name
      description = "Service Connect namespace for $${var.namespace_name}"
      tags        = var.tags
    }

    output "namespace_arn" {
      description = "ARN do namespace. Consumido por ecs-cluster (default) e pelos services."
      value       = aws_service_discovery_http_namespace.this.arn
    }

    output "namespace_id" {
      value = aws_service_discovery_http_namespace.this.id
    }

    output "namespace_name" {
      value = aws_service_discovery_http_namespace.this.name
    }
  EOF
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  environment      = local.environment_vars.locals.environment
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
  # Naming espelha staging (rvt-staging.local).
  namespace_name = "rvt-${local.environment}.local"
  tags           = dependency.tags.outputs.tags
}
