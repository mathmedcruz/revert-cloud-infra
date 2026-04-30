terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/service?ref=v7.5.0"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region

  # SINGLETON. django_celery_beat lê tabelas Postgres a cada N seg e enfileira;
  # rodar 2 instâncias simultâneas duplica todas as tarefas periódicas.
  # Comando real (no task-def gerenciado pelo CI):
  #   celery -A nix_webserver beat --scheduler django_celery_beat.schedulers:DatabaseScheduler --pidfile=
  service_name = "svc-${local.environment}-nix_webserver-beat"
  task_family  = "td-${local.environment}-nix_webserver-beat"
  container    = "nix_webserver_beat"
  log_group    = "/ecs/${local.environment}/nix_webserver/beat"
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

inputs = {
  name        = local.service_name
  family      = local.task_family
  cluster_arn = dependency.ecs_cluster.outputs.arn

  # Beat é leve (só agenda, não processa) — 0.25 vCPU / 512MB basta.
  cpu           = 256
  memory        = 512
  desired_count = 1

  launch_type      = "FARGATE"
  assign_public_ip = false
  subnet_ids       = dependency.vpc.outputs.private_subnets

  create_security_group        = true
  security_group_name          = "${local.service_name}-task"
  security_group_ingress_rules = {}
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound (Redis broker, RDS, external)"
    }
  }

  container_definitions = {
    (local.container) = {
      image                  = "nginx:alpine"
      essential              = true
      readonlyRootFilesystem = false

      cloudwatch_log_group_name              = local.log_group
      cloudwatch_log_group_retention_in_days = 14
    }
  }

  # Crítico: durante deploy, ECS DEVE matar a task antiga ANTES de subir a nova.
  # Default (min=100, max=200) sobreporia 2 instâncias por ~30s. Trade-off
  # aceito: ~30-60s sem beat durante rollout (scheduler é tolerante).
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  ignore_task_definition_changes = true

  # IAM role names curtos (limite AWS name_prefix = 38 chars; default estouraria).
  task_exec_iam_role_use_name_prefix = false
  task_exec_iam_role_name            = "dev-nix-beat-exec"
  tasks_iam_role_use_name_prefix     = false
  tasks_iam_role_name                = "dev-nix-beat-task"

  tags = dependency.tags.outputs.tags
}
