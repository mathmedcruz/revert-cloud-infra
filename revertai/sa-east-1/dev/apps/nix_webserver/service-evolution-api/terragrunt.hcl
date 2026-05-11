terraform {
  source = "${get_parent_terragrunt_dir()}/modules/ecs-service-app-managed"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region
  vpc_cidr    = local.environment_vars.locals.vpc_cidr

  # Evolution API (WhatsApp gateway) — imagem terceira `evoapicloud/evolution-api`,
  # NÃO é buildada pelo CI do nix_webserver. Task-def real (registrada fora do
  # bootstrap) usa family `td-${env}-nix-evolution-api` e container `evolution_api`
  # — bate com o template aqui pra evitar fósseis com nome divergente.
  service_name = "svc-${local.environment}-nix-evolution-api"
  task_family  = "td-${local.environment}-nix-evolution-api"
  container    = "evolution_api"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vpc" {
  config_path = "../../../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    private_subnets = ["subnet-00000000", "subnet-00000001", "subnet-00000002"]
  }
}

dependency "ecs_cluster" {
  config_path = "../../../ecs-cluster"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    arn = "arn:aws:ecs:sa-east-1:000000000000:cluster/dummy"
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

dependency "iam" {
  config_path = "../iam"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    task_exec_iam_role_arn = "arn:aws:iam::000000000000:role/dummy-exec"
    tasks_iam_role_arn     = "arn:aws:iam::000000000000:role/dummy-task"
  }
}

inputs = {
  name           = local.service_name
  family         = local.task_family
  container_name = local.container
  cluster_arn    = dependency.ecs_cluster.outputs.arn
  region         = local.region
  subnet_ids     = dependency.vpc.outputs.private_subnets

  task_exec_iam_role_arn = dependency.iam.outputs.task_exec_iam_role_arn
  tasks_iam_role_arn     = dependency.iam.outputs.tasks_iam_role_arn

  desired_count = 1

  # Ingress 8080 do VPC inteiro: web/workers do nix_webserver chamam a Evolution
  # via DNS interno (EVOLUTION_API_URL). Sem ALB — é tráfego task→task. Apertar
  # pra SGs específicos exigiria referência cruzada entre stacks de service.
  security_group_name = "${local.service_name}-task"
  security_group_ingress_rules = {
    from_vpc_http = {
      from_port   = 8080
      to_port     = 8080
      ip_protocol = "tcp"
      cidr_ipv4   = local.vpc_cidr
      description = "Evolution API HTTP from VPC (nix_webserver tasks)"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound (RDS, Redis, WhatsApp Cloud)"
    }
  }

  # Service Connect SERVER. Publica alias `evolution-api:8080` no namespace
  # default do cluster (rvt-${env}.local). Web/workers resolvem
  # `http://evolution-api.rvt-dev.local:8080` via envoy sidecar.
  #
  # `port_name` TEM que bater com `portMappings[].name` em
  # nix_webserver/task-definitions/evolution-api.json (`evolution-api-8080`).
  # Mismatch → ECS aceita config mas NÃO publica o alias.
  service_connect_configuration = {
    enabled = true
    service = [{
      port_name      = "evolution-api-8080"
      discovery_name = "evolution-api"
      client_alias = {
        port     = 8080
        dns_name = "evolution-api"
      }
    }]
  }

  tags = dependency.tags.outputs.tags
}
