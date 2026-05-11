terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/cluster?ref=v7.5.0"
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

# Cloud Map namespace usado pelo Service Connect. Setando aqui no cluster
# vira o default — services não precisam repetir `namespace` no
# `service_connect_configuration` deles, basta `enabled = true`.
dependency "cloudmap" {
  config_path = "../cloudmap"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    namespace_arn = "arn:aws:servicediscovery:sa-east-1:000000000000:namespace/ns-mock"
  }
}

inputs = {
  name = "${local.app_name}-${local.environment}"

  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 100
      }
    }
  }

  # Default namespace pra Service Connect. Qualquer service que setar
  # `service_connect_configuration.enabled = true` herda esse namespace
  # automaticamente — não precisa repetir o ARN em cada service.
  service_connect_defaults = {
    namespace = dependency.cloudmap.outputs.namespace_arn
  }

  tags = dependency.tags.outputs.tags
}
