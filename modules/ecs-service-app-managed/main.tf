# ============================================================================
# Bootstrap task-def
# ----------------------------------------------------------------------------
# Cria revision 1 da family — ÚNICA E SOMENTE pra que o aws_ecs_service tenha
# onde apontar no primeiro `terragrunt apply`. Depois disso o CI workflow do
# nix_webserver registra revision 2, 3, 4... e atualiza o service via
# UpdateService.
#
# `lifecycle.ignore_changes = all` faz Terraform NUNCA mais comparar essa
# task-def com o estado real ou com o código. Mesmo se você bumpar a versão
# do módulo upstream, mudar cpu/memory aqui, ou se a revision 1 for
# deregistered manualmente em AWS, plan ignora.
#
# A revision 1 vira fóssil — ninguém usa após o primeiro deploy do CI.
# ============================================================================

resource "aws_ecs_task_definition" "bootstrap" {
  family                   = var.family
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  execution_role_arn = var.task_exec_iam_role_arn
  task_role_arn      = var.tasks_iam_role_arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = "public.ecr.aws/docker/library/busybox:latest"
      essential = true
      command   = ["sh", "-c", "sleep infinity"]
    }
  ])

  tags = var.tags

  lifecycle {
    ignore_changes = all
  }
}

# ============================================================================
# Service
# ----------------------------------------------------------------------------
# Usa o módulo upstream `terraform-aws-modules/ecs/aws//modules/service@7.5.0`
# com `create_task_definition = false` (módulo NÃO cria task-def — usamos a
# nossa bootstrap acima) e `ignore_task_definition_changes = true` (service
# pointer fica livre pro CI atualizar).
# ============================================================================

module "service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "7.5.0"

  name        = var.name
  cluster_arn = var.cluster_arn
  region      = var.region

  desired_count    = var.desired_count
  launch_type      = "FARGATE"
  assign_public_ip = false
  subnet_ids       = var.subnet_ids

  create_security_group        = true
  security_group_name          = var.security_group_name
  security_group_ingress_rules = var.security_group_ingress_rules
  security_group_egress_rules  = var.security_group_egress_rules

  load_balancer                     = var.load_balancer
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  # Task-def é gerenciada por NÓS (resource bootstrap acima) + pelo CI.
  # Módulo upstream apenas referencia o ARN; nunca cria nem atualiza.
  create_task_definition         = false
  task_definition_arn            = aws_ecs_task_definition.bootstrap.arn
  ignore_task_definition_changes = true

  # IAM roles vêm de fora (../iam stack). Módulo não cria.
  create_task_exec_iam_role = false
  task_exec_iam_role_arn    = var.task_exec_iam_role_arn
  create_tasks_iam_role     = false
  tasks_iam_role_arn        = var.tasks_iam_role_arn

  tags = var.tags
}
