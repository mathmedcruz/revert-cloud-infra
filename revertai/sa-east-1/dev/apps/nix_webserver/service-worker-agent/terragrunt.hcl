terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/service?ref=v7.5.0"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region

  # Worker da fila `agent`: tarefas dos agentes (Maia, Curator, Bushido, Pacman).
  # Pool isolado pra que um agente travado não derrube as filas high/low.
  # Comando real (no task-def gerenciado pelo CI):
  #   celery -A nix_webserver worker -Q agent --pool=prefork --concurrency=2 --max-tasks-per-child=1000
  service_name = "svc-${local.environment}-nix_webserver-worker-agent"
  task_family  = "td-${local.environment}-nix_webserver-worker-agent"
  container    = "nix_webserver_worker_agent"
  log_group    = "/ecs/${local.environment}/nix_webserver/worker-agent"
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

  cpu           = 512
  memory        = 1024
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
      description = "Allow all outbound (RDS, Redis, S3, external APIs)"
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

  ignore_task_definition_changes = true

  # IAM role names curtos (limite AWS name_prefix = 38 chars; default estouraria).
  task_exec_iam_role_use_name_prefix = false
  task_exec_iam_role_name            = "dev-nix-wrk-agt-exec"
  tasks_iam_role_use_name_prefix     = false
  tasks_iam_role_name                = "dev-nix-wrk-agt-task"

  tags = dependency.tags.outputs.tags
}
