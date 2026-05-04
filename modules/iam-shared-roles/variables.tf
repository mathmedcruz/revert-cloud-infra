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
