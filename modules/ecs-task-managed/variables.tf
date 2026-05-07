# ============================================================================
# Identificação
# ============================================================================

variable "family" {
  type        = string
  description = "Family name da task-def (ex.: td-dev-nix-db-import). Bootstrap registra revisão 1; CI/workflow registra revisões reais."
}

variable "container_name" {
  type        = string
  description = "Nome do container dentro da task-def. TEM que bater com `containerDefinitions[].name` no JSON usado pelo workflow (task-definitions/db-import.json)."
}

variable "region" {
  type        = string
  description = "AWS region. Repassada ao log group e à task-def."
}

# ============================================================================
# IAM
# ============================================================================

variable "task_exec_iam_role_arn" {
  type        = string
  description = "Role usada pelo agente ECS pra puxar imagem e injetar secrets. Bootstrap task-def referencia esta role."
}

variable "tasks_iam_role_arn" {
  type        = string
  description = "Role assumida pelo código dentro do container."
}

# ============================================================================
# Compute (defaults batem com os outros módulos do repo: ARM64 / Fargate / 256 / 512)
# ============================================================================

variable "cpu" {
  type    = string
  default = "256"
}

variable "memory" {
  type    = string
  default = "512"
}

variable "cpu_architecture" {
  type    = string
  default = "ARM64"
}

variable "operating_system_family" {
  type    = string
  default = "LINUX"
}

# ============================================================================
# Bootstrap container image
# ============================================================================

variable "bootstrap_image" {
  type        = string
  default     = "public.ecr.aws/docker/library/busybox:latest"
  description = "Imagem do bootstrap. Workflow sobrescreve a imagem real ao registrar revisão nova; esta aqui só existe pra a revisão 1 ser válida."
}

variable "bootstrap_command" {
  type        = list(string)
  default     = ["sh", "-c", "sleep infinity"]
  description = "Command do bootstrap. Apenas pra revisão 1 ser válida — workflow sempre passa command override no run-task."
}

# ============================================================================
# Logs
# ============================================================================

variable "log_group_name" {
  type        = string
  description = "Nome do CloudWatch Log Group (ex.: /ecs/dev/nix-db-import). Mesmo valor referenciado pelo JSON do workflow."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retenção do log group. 0 = nunca expira (default da AWS quando ECS auto-cria)."
}

# ============================================================================
# Tags
# ============================================================================

variable "tags" {
  type    = map(string)
  default = {}
}
