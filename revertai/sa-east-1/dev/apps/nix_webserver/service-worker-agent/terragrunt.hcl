terraform {
  source = "${get_parent_terragrunt_dir()}/modules/ecs-service-app-managed"
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

  security_group_name          = "${local.service_name}-task"
  security_group_ingress_rules = {}
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound (RDS, Redis, S3, external APIs)"
    }
  }

  tags = dependency.tags.outputs.tags
}
