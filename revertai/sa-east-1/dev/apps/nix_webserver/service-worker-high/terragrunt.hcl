terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/service?ref=v7.5.0"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region

  # Worker da fila `high`: tarefas urgentes (SLA 60s no QUEUE_SLA do Django).
  # Comando real (no task-def gerenciado pelo CI):
  #   celery -A nix_webserver worker -Q high --pool=prefork --concurrency=4 --max-tasks-per-child=1000
  service_name = "svc-${local.environment}-nix_webserver-worker-high"
  task_family  = "td-${local.environment}-nix_webserver-worker-high"
  container    = "nix_webserver_worker_high"
  log_group    = "/ecs/${local.environment}/nix_webserver/worker-high"
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
  name        = local.service_name
  family      = local.task_family
  cluster_arn = dependency.ecs_cluster.outputs.arn

  cpu           = 512
  memory        = 1024
  desired_count = 1

  launch_type      = "FARGATE"
  assign_public_ip = false
  subnet_ids       = dependency.vpc.outputs.private_subnets

  # Workers não recebem inbound — ingress vazio. Só egress (RDS, Redis, APIs externas).
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

  # Sem portMappings (não escuta porta) e sem load_balancer.
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

  # Roles compartilhadas entre todos os services do nix_webserver — criadas em ../iam.
  create_task_exec_iam_role = false
  task_exec_iam_role_arn    = dependency.iam.outputs.task_exec_iam_role_arn
  create_tasks_iam_role     = false
  tasks_iam_role_arn        = dependency.iam.outputs.tasks_iam_role_arn

  tags = dependency.tags.outputs.tags
}
