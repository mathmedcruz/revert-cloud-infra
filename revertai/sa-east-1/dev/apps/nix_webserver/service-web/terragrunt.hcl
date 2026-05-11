terraform {
  source = "${get_parent_terragrunt_dir()}/modules/ecs-service-app-managed"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region

  # Identificadores referenciados pelo CI no fluxo de deploy
  # (.github/workflows/_deploy.yml do nix_webserver). Mudar aqui exige
  # mudança correspondente no workflow.
  service_name = "svc-${local.environment}-nix_webserver-web"
  task_family  = "td-${local.environment}-nix_webserver-web"
  container    = "nix_webserver_web"
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

dependency "alb" {
  config_path = "../../../alb"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    security_group_id = "sg-00000000"
  }
}

dependency "alb_target" {
  config_path = "../alb-target"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    target_group_arn = "arn:aws:elasticloadbalancing:sa-east-1:000000000000:targetgroup/dummy/00000000"
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

  # SG do task — único service do nix com ingress (recebe do ALB).
  security_group_name = "${local.service_name}-task"
  security_group_ingress_rules = {
    from_alb = {
      from_port                    = 8000
      to_port                      = 8000
      ip_protocol                  = "tcp"
      referenced_security_group_id = dependency.alb.outputs.security_group_id
      description                  = "App port ingress from shared ALB"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound (RDS, Redis, S3, external APIs)"
    }
  }

  load_balancer = {
    service = {
      target_group_arn = dependency.alb_target.outputs.target_group_arn
      # container_name TEM que bater com o `name` em
      # nix_webserver/task-definitions/web.json (`nix_webserver_web`).
      container_name = local.container
      container_port = 8000
    }
  }

  # Django + tenants + collectstatic em entrypoint pode levar 60-120s.
  health_check_grace_period_seconds = 180

  # Service Connect CLIENT-only. Sem `service` = não publica alias (web é
  # alcançado via ALB, não via SC). Apenas habilita o envoy sidecar pra
  # resolver `evolution-api.rvt-dev.local:8080` quando o app chama
  # EVOLUTION_API_URL.
  # Namespace herda do cluster (service_connect_defaults).
  service_connect_configuration = {
    enabled = true
  }

  tags = dependency.tags.outputs.tags
}
