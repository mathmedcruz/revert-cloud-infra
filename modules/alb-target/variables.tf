variable "name" {
  type        = string
  description = "Short name used to prefix the target group (tg-<name>). Limit: ~22 chars so the full name fits AWS's 32-char cap."
}

variable "vpc_id" {
  type = string
}

variable "container_port" {
  type        = number
  description = "Port the container listens on (target group port)."
}

variable "alb_listener_arn" {
  type        = string
  description = "ARN of the ALB listener where the listener rule will be attached."
}

variable "host" {
  type        = list(string)
  description = "Host header values routed to this target group. ALB host_header rule aceita até 5 valores; pra app single-host, passar lista de 1 (ex: ['example.dev.internal']). Pra apps multi-tenant, passar apex + wildcard (ex: ['api.dev...', '*.api.dev...'])."
}

variable "listener_rule_priority" {
  type        = number
  description = "Priority for the listener rule (1-50000). Must be unique per listener."
}

variable "health_check_path" {
  type    = string
  default = "/"
}

variable "health_check_matcher" {
  type    = string
  default = "200-299"
}

variable "tags" {
  type    = map(string)
  default = {}
}
