# ============================================================================
# Identificação
# ============================================================================

variable "name" {
  type        = string
  description = "Nome do ECS service (ex.: svc-dev-nix_webserver-web)."
}

variable "family" {
  type        = string
  description = "Family name da task-def (ex.: td-dev-nix_webserver-web). Usada tanto pelo bootstrap quanto pelas revisions futuras do CI."
}

variable "container_name" {
  type        = string
  description = "Nome do container dentro da task-def. TEM que bater com `containerDefinitions[].name` nos JSONs do CI (nix_webserver/task-definitions/*.json) — usado também por loadBalancer.containerName quando aplicável."
}

variable "cluster_arn" {
  type        = string
  description = "ARN do ECS cluster onde o service vai rodar."
}

variable "region" {
  type        = string
  description = "AWS region. Repassada ao módulo upstream."
}

# ============================================================================
# Network
# ============================================================================

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets privadas onde as tasks rodam."
}

# ============================================================================
# IAM (consumido pelo bootstrap task-def)
# ============================================================================

variable "task_exec_iam_role_arn" {
  type        = string
  description = "Role usada pelo agente ECS pra puxar imagem e injetar secrets. Bootstrap task-def referencia esta role; CI também (via JSON com placeholder)."
}

variable "tasks_iam_role_arn" {
  type        = string
  description = "Role assumida pelo código da app dentro do container."
}

# ============================================================================
# Service config
# ============================================================================

variable "desired_count" {
  type    = number
  default = 1
}

# ============================================================================
# Security group
# ============================================================================

variable "security_group_name" {
  type = string
}

variable "security_group_ingress_rules" {
  type    = any
  default = {}
}

variable "security_group_egress_rules" {
  type    = any
  default = {}
}

# ============================================================================
# Load balancer (opcional — apenas pro service web)
# ============================================================================

variable "load_balancer" {
  type        = any
  default     = null
  description = "Map com configs de LB. Null pra services que não recebem tráfego HTTP (workers, beat)."
}

variable "health_check_grace_period_seconds" {
  type    = number
  default = null
}

# ============================================================================
# Deployment policy (relevante pro beat singleton)
# ============================================================================

variable "deployment_minimum_healthy_percent" {
  type    = number
  default = null
}

variable "deployment_maximum_percent" {
  type    = number
  default = null
}

# ============================================================================
# Tags
# ============================================================================

variable "tags" {
  type    = map(string)
  default = {}
}
