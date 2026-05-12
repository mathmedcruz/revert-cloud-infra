# Cloud Map Private DNS namespace usado por ECS service discovery (modo clássico).
# Cria UM namespace `rvt-${env}.local` (ex.: rvt-dev.local) com uma Private Hosted
# Zone do Route53 atrelada. Tasks ECS registram A records (multivalue) sob esse
# namespace via `aws_service_discovery_service` + `service_registries` no ECS service.
#
# Por que Private DNS (e não HTTP namespace + Service Connect):
#   - Resolução DNS é nativa (Route53 + VPC resolver) — qualquer recurso na VPC
#     resolve, não só tasks ECS com envoy sidecar.
#   - Sem overhead de envoy (~256 MiB + 50 mCPU/task).
#   - Espelha o setup de staging (rvt-staging.local).
#   - Custo: $0.50/mês pela Private Hosted Zone + Route53 queries (baixo em dev).
#   - Trade-off: stale endpoint até TTL (default 30s aqui) quando task morre,
#     e sem métricas L7 que o SC oferece de graça.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Namespace é um recurso AWS único por VPC; não precisa de módulo dedicado.
# Inline aqui pra evitar sobrecarga de criar diretório `modules/cloudmap/`
# pra um único `aws_service_discovery_private_dns_namespace`.
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
      description = "Nome do Private DNS namespace (ex.: rvt-dev.local). Vira o sufixo DNS dos services."
    }

    variable "vpc_id" {
      type        = string
      description = "VPC onde a Private Hosted Zone será atrelada."
    }

    variable "tags" {
      type    = map(string)
      default = {}
    }

    resource "aws_service_discovery_private_dns_namespace" "this" {
      name        = var.namespace_name
      description = "Cloud Map Private DNS namespace for $${var.namespace_name}"
      vpc         = var.vpc_id
      tags        = var.tags
    }

    output "namespace_arn" {
      description = "ARN do namespace. Consumido pelos services que registram via aws_service_discovery_service."
      value       = aws_service_discovery_private_dns_namespace.this.arn
    }

    output "namespace_id" {
      description = "ID do namespace. Consumido pelo aws_service_discovery_service.dns_config.namespace_id."
      value       = aws_service_discovery_private_dns_namespace.this.id
    }

    output "namespace_name" {
      value = aws_service_discovery_private_dns_namespace.this.name
    }

    output "hosted_zone_id" {
      description = "ID da Private Hosted Zone Route53 criada pelo namespace. Útil pra debug."
      value       = aws_service_discovery_private_dns_namespace.this.hosted_zone
    }
  EOF
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  environment      = local.environment_vars.locals.environment
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    vpc_id = "vpc-00000000"
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
  # Naming espelha staging (rvt-staging.local).
  namespace_name = "rvt-${local.environment}.local"
  vpc_id         = dependency.vpc.outputs.vpc_id
  tags           = dependency.tags.outputs.tags
}
