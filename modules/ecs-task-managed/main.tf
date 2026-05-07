# ============================================================================
# ecs-task-managed
# ----------------------------------------------------------------------------
# Para WORKLOADS ONE-SHOT (run-task), não para services de longa duração.
# Diferente de `ecs-service-app-managed`, este módulo NÃO cria aws_ecs_service
# nem security group de service — só:
#   1. CloudWatch Log Group (com retention controlado, evita default infinito
#      do ECS auto-create);
#   2. aws_ecs_task_definition bootstrap (revision 1, vestigial — workflow
#      registra revision 2+ via aws ecs register-task-definition).
#
# Dispara via `aws ecs run-task --task-definition <family>:<rev>` direto;
# rede/SG vêm do override no run-task (a workflow do GH Actions reusa
# WEB_SG / PRIVATE_SUBNETS).
# ============================================================================

resource "aws_cloudwatch_log_group" "this" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_ecs_task_definition" "bootstrap" {
  family                   = var.family
  cpu                      = var.cpu
  memory                   = var.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = var.operating_system_family
  }

  execution_role_arn = var.task_exec_iam_role_arn
  task_role_arn      = var.tasks_iam_role_arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.bootstrap_image
      essential = true
      command   = var.bootstrap_command
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}
