terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/service?ref=v7.5.0"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region

  # Os 4 identificadores abaixo são referenciados pelo CI no fluxo de deploy
  # (render-task-definition + deploy-task-definition). Mudar aqui exige
  # mudança correspondente no .github/workflows/deploy.yml do nix_webserver.
  service_name = "svc-${local.environment}-nix_webserver-web"
  task_family  = "td-${local.environment}-nix_webserver-web"
  container    = "nix_webserver_web"
  log_group    = "/ecs/${local.environment}/nix_webserver/web"
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

inputs = {
  name        = local.service_name
  family      = local.task_family
  cluster_arn = dependency.ecs_cluster.outputs.arn

  # AJUSTE: tamanho do container Fargate. Web é o que sustenta tráfego HTTP;
  # ajustar conforme p99 de latência observado.
  cpu           = 512
  memory        = 1024
  desired_count = 1

  launch_type      = "FARGATE"
  assign_public_ip = false
  subnet_ids       = dependency.vpc.outputs.private_subnets

  # SG do task — único service do nix com ingress (recebe do ALB).
  create_security_group = true
  security_group_name   = "${local.service_name}-task"
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

  # Bootstrap container definition. CI sobrescreve image, command, env, secrets
  # a cada deploy. ignore_task_definition_changes = true preserva essas mudanças.
  container_definitions = {
    (local.container) = {
      image                  = "nginx:alpine"
      essential              = true
      readonlyRootFilesystem = false

      portMappings = [
        {
          name          = local.container
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      cloudwatch_log_group_name              = local.log_group
      cloudwatch_log_group_retention_in_days = 14
    }
  }

  load_balancer = {
    service = {
      target_group_arn = dependency.alb_target.outputs.target_group_arn
      container_name   = local.container
      container_port   = 8000
    }
  }

  # Django + tenants + collectstatic em entrypoint pode levar 60-120s.
  # 180s = margem confortável (dificuldade #14 do plan).
  health_check_grace_period_seconds = 180

  ignore_task_definition_changes = true

  tags = dependency.tags.outputs.tags
}
