variable "name_prefix" {
  type        = string
  description = "Prefixo das roles. Ex.: 'dev-nix' produz 'dev-nix-ecs-exec' e 'dev-nix-ecs-task'."
}

variable "account_id" {
  type        = string
  description = "AWS account ID — usado na condição aws:SourceAccount do trust da tasks role."
}

variable "region" {
  type        = string
  description = "AWS region — usado na condição aws:SourceArn do trust da tasks role."
}

variable "tags" {
  type        = map(string)
  description = "Tags aplicadas em ambas as roles."
  default     = {}
}

variable "exec_managed_policy_arns" {
  type        = list(string)
  description = "ARNs de policies (AWS-managed ou customer-managed) a anexar à execution role."
  default     = []
}

variable "exec_inline_policies" {
  type        = map(string)
  description = "Inline policies extras anexadas à execution role. Map de nome → JSON."
  default     = {}
}

variable "task_managed_policy_arns" {
  type        = list(string)
  description = "ARNs de policies a anexar à tasks role."
  default     = []
}

variable "task_inline_policies" {
  type        = map(string)
  description = "Inline policies anexadas à tasks role. Map de nome → JSON."
  default     = {}
}
