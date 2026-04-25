terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/service?ref=v7.5.0"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region

  # Matches the naming the CircleCI pipeline references.
  service_name = "svc-${local.environment}-example"
  task_family  = "td-${local.environment}-example"
  container    = "example"
  log_group    = "/ecs/${local.environment}/example"
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

  cpu              = 256
  memory           = 512
  desired_count    = 1
  launch_type      = "FARGATE"
  assign_public_ip = false
  subnet_ids       = dependency.vpc.outputs.private_subnets

  # SG created by the module. Ingress from the shared ALB SG on the container port.
  # v7 of the module uses the newer aws_vpc_security_group_{ingress,egress}_rule
  # schema: ip_protocol (not protocol), cidr_ipv4 (not cidr_blocks),
  # referenced_security_group_id (not source_security_group_id).
  create_security_group = true
  security_group_name   = "${local.service_name}-task"
  security_group_ingress_rules = {
    from_alb = {
      from_port                    = 80
      to_port                      = 80
      ip_protocol                  = "tcp"
      referenced_security_group_id = dependency.alb.outputs.security_group_id
      description                  = "App port ingress from shared ALB"
    }
  }
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound"
    }
  }

  # Bootstrap container definition. CI replaces image/env on every deploy via
  # aws-ecs/update_task_definition; ignore_task_definition_changes below keeps
  # Terraform from reverting those revisions.
  container_definitions = {
    (local.container) = {
      image                  = "nginx:alpine"
      essential              = true
      readonlyRootFilesystem = false

      portMappings = [
        {
          name          = local.container
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      cloudwatch_log_group_name              = local.log_group
      cloudwatch_log_group_retention_in_days = 14
    }
  }

  tasks_iam_role_permissions_boundary     = "arn:aws:iam::175209828699:policy/terragrunt-pipeline-boundary"
  task_exec_iam_role_permissions_boundary = "arn:aws:iam::175209828699:policy/terragrunt-pipeline-boundary"

  load_balancer = {
    service = {
      target_group_arn = dependency.alb_target.outputs.target_group_arn
      container_name   = local.container
      container_port   = 80
    }
  }

  health_check_grace_period_seconds = 60

  # CI owns the task definition after bootstrap.
  ignore_task_definition_changes = true

  tags = dependency.tags.outputs.tags
}
