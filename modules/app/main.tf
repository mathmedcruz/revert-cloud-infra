locals {
  task_family  = "td-${var.environment}-${var.name}"
  service_name = "svc-${var.environment}-${var.name}"
  log_group    = "/ecs/${var.environment}/${var.name}"
  ecr_name     = "${var.environment}-${var.name}"
}

# ----------------------------------------------------------------------------
# ECR repository — CircleCI pushes the app image here.
# Not covered by the upstream service module.
# ----------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  name                 = local.ecr_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# ----------------------------------------------------------------------------
# Target group + listener rule — only when exposed via ALB.
# Not covered by the upstream service module (the module just consumes the TG ARN).
# ----------------------------------------------------------------------------
resource "aws_lb_target_group" "this" {
  count = var.expose_via_alb ? 1 : 0

  # Target group name hard limit = 32 chars.
  name        = substr("tg-${var.environment}-${var.name}", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "this" {
  count = var.expose_via_alb ? 1 : 0

  listener_arn = var.alb_listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  condition {
    host_header {
      values = [var.host]
    }
  }

  tags = var.tags
}

# ----------------------------------------------------------------------------
# ECS service + task definition + IAM roles + SG + log group via the
# upstream terraform-aws-modules/ecs//modules/service module.
#
# We set ignore_task_definition_changes = true so CircleCI owns task-def
# revisions after the bootstrap apply.
# ----------------------------------------------------------------------------
module "service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.12"

  name        = local.service_name
  family      = local.task_family
  cluster_arn = var.ecs_cluster_arn

  cpu              = var.cpu
  memory           = var.memory
  desired_count    = var.desired_count
  launch_type      = "FARGATE"
  assign_public_ip = false
  subnet_ids       = var.private_subnet_ids

  # Security group managed by the module. Egress open, ingress from ALB only
  # when the service is ALB-exposed.
  create_security_group = true
  security_group_name   = "${local.service_name}-task"
  security_group_rules = merge(
    {
      egress_all = {
        type        = "egress"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
      }
    },
    var.expose_via_alb ? {
      ingress_from_alb = {
        type                     = "ingress"
        from_port                = var.container_port
        to_port                  = var.container_port
        protocol                 = "tcp"
        source_security_group_id = var.alb_security_group_id
        description              = "App port ingress from shared ALB"
      }
    } : {}
  )

  # Initial container definition. Image is dummy — CI will replace the image
  # (and optionally cpu/memory/env vars) on every deploy via
  # aws-ecs/update_task_definition. ignore_task_definition_changes below
  # prevents Terraform from reverting those CI-driven revisions.
  container_definitions = {
    (var.name) = {
      image                    = "nginx:alpine"
      essential                = true
      readonly_root_filesystem = false
      command                  = length(var.command) > 0 ? var.command : null

      port_mappings = var.expose_via_alb ? [
        {
          name          = var.name
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ] : []

      cloudwatch_log_group_name              = local.log_group
      cloudwatch_log_group_retention_in_days = var.log_retention_days
    }
  }

  load_balancer = var.expose_via_alb ? {
    service = {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = var.name
      container_port   = var.container_port
    }
  } : {}

  health_check_grace_period_seconds = var.expose_via_alb ? 60 : null

  # Option A: CI owns the task definition after bootstrap.
  ignore_task_definition_changes = true

  tags = var.tags

  depends_on = [aws_lb_listener_rule.this]
}
