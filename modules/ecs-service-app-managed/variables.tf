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
# Service Connect (ECS-managed envoy sidecar pra IPC service-to-service)
# ============================================================================

variable "service_connect_configuration" {
  type        = any
  default     = null
  description = <<-EOT
    Config de Service Connect (alternativa ao Cloud Map clássico — usar UM dos dois).
    null (default) = sem SC. {} também ligaria SC porque o upstream tipa esse
    input como object com `enabled = optional(bool, true)` — `{}` faria o `for_each`
    do upstream criar o bloco com `enabled = true` e quebrar no apply quando o
    cluster não tem `service_connect_defaults.namespace`. Modos:
      - Server (publica alias): { enabled = true, service = [{ port_name, client_alias = { ... } }] }
      - Client only (resolve aliases): { enabled = true } (sem `service`)
    O envoy sidecar adiciona ~256 MiB de memory + ~50 mCPU por task — confirmar
    que cpu/memory da task-def comporta antes de habilitar.
  EOT
}

# ============================================================================
# Cloud Map clássico (Private DNS namespace + service_registries)
# ============================================================================

variable "cloud_map_service" {
  type        = any
  default     = null
  description = <<-EOT
    Config pra registrar o ECS service num Cloud Map service (modo clássico,
    alternativo ao Service Connect). null (default) = não cria.

    Quando setado, cria um `aws_service_discovery_service` no namespace passado
    em `cloud_map_namespace_id` e amarra o ECS service nele via `service_registries`.
    ECS Agent registra/desregistra A records (multivalue) na Private Hosted Zone
    do namespace conforme tasks sobem/morrem.

    Schema:
      {
        name           = string             # nome do service no Cloud Map (vira <name>.<namespace>)
        ttl            = optional(number)   # TTL do A record. Default 30s.
        container_name = optional(string)   # default: var.container_name
        container_port = optional(number)   # default: null (usa porta única do task-def)
      }

    Sem overhead de envoy. Trade-off: stale endpoint até TTL quando task morre,
    sem métricas L7. Usar `service_connect_configuration` OU `cloud_map_service`,
    NÃO os dois ao mesmo tempo.
  EOT
}

variable "cloud_map_namespace_id" {
  type        = string
  default     = null
  description = "ID do Private DNS namespace (vindo de cloudmap/ outputs). Obrigatório quando cloud_map_service != null."
}

# ============================================================================
# Tags
# ============================================================================

variable "tags" {
  type    = map(string)
  default = {}
}
