# ============================================================================
# Bootstrap task-def
# ----------------------------------------------------------------------------
# Cria revision 1 da family — ÚNICA E SOMENTE pra que o aws_ecs_service tenha
# onde apontar no primeiro `terragrunt apply`. Depois disso o CI workflow do
# nix_webserver registra revision 2, 3, 4... e atualiza o service via
# UpdateService.
#
# Proteção do estado da aplicação está em `ignore_task_definition_changes`
# DO SERVICE (módulo upstream), que segura o service pointer no que o CI
# definiu. Esta resource (bootstrap) NÃO tem ignore_changes — se você mudar
# algo aqui, replace acontece, mas como o service ignora task_definition
# changes, o app continua rodando o que o CI cravou. As revisions antigas
# do bootstrap viram fósseis (deregistered, nada referencia).
# ============================================================================

locals {
  # Se o service tem load_balancer, ECS exige que o container declarado em
  # `loadBalancer.containerName` tenha o `loadBalancer.containerPort` em
  # `portMappings`. Senão, CreateService falha:
  #   "The container X did not have a container port Y defined"
  #
  # Workers/beat passam load_balancer=null → portMappings vazio (não escutam
  # porta). Web passa o map com container_port=8000 → portMapping é incluído.
  bootstrap_port_mappings = try(
    [{
      name          = var.container_name
      containerPort = var.load_balancer.service.container_port
      hostPort      = var.load_balancer.service.container_port
      protocol      = "tcp"
    }],
    []
  )
}

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
      name         = var.container_name
      image        = "public.ecr.aws/docker/library/busybox:latest"
      essential    = true
      command      = ["sh", "-c", "sleep infinity"]
      portMappings = local.bootstrap_port_mappings
    }
  ])

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# Cloud Map service discovery (modo clássico — Private DNS namespace)
# ----------------------------------------------------------------------------
# Cria `aws_service_discovery_service` SÓ se `var.cloud_map_service != null`.
# O service ECS abaixo passa o ARN desse recurso em `service_registries`, e o
# ECS Agent registra/desregistra os IPs das tasks como A records (multivalue)
# na Private Hosted Zone do namespace.
#
# routing_policy = MULTIVALUE → Route53 retorna até 8 IPs no response; cliente
# escolhe um aleatório (DNS round-robin). Cada task viva = 1 A record.
#
# health_check_custom_config: ECS marca instância UP/DOWN baseado no task status
# (RUNNING/STOPPED). Route53 health checks ATIVOS adicionariam custo $0.50/check
# e exigiriam endpoint público — não usamos.
# ============================================================================

resource "aws_service_discovery_service" "this" {
  count = var.cloud_map_service != null ? 1 : 0

  name = var.cloud_map_service.name

  dns_config {
    namespace_id   = var.cloud_map_namespace_id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = try(var.cloud_map_service.ttl, 30)
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = var.tags
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

  # Service Connect: passa o map cru pro upstream. {} = SC desligado.
  # Quando ligado, ECS injeta envoy sidecar automático na task.
  service_connect_configuration = var.service_connect_configuration

  # Cloud Map clássico: registra o ECS service no aws_service_discovery_service
  # criado acima. ECS Agent registra/desregistra A records conforme tasks sobem/morrem.
  # Upstream tipa service_registries como object({..., registry_arn = string}) com
  # default = null — passar {} quebra type-check porque registry_arn é obrigatório.
  service_registries = var.cloud_map_service != null ? {
    registry_arn   = aws_service_discovery_service.this[0].arn
    container_name = try(var.cloud_map_service.container_name, var.container_name)
    container_port = try(var.cloud_map_service.container_port, null)
  } : null

  tags = var.tags
}
