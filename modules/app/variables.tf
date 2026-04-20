variable "name" {
  type        = string
  description = "Service short name. Used in resource naming (e.g. 'nix-webserver', 'nix-celery-worker-high')."
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prd). Used in resource naming."
}

variable "region" {
  type        = string
  description = "AWS region (used by the awslogs log driver)."
}

variable "ecs_cluster_arn" {
  type        = string
  description = "ARN of the ECS cluster that will host this service."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the task ENIs will live."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets the Fargate tasks run in."
}

variable "cpu" {
  type        = number
  default     = 256
  description = "Task CPU units (256/512/1024/2048/4096). See Fargate compatibility matrix."
}

variable "memory" {
  type        = number
  default     = 512
  description = "Task memory MiB. Must be compatible with the chosen CPU."
}

variable "desired_count" {
  type        = number
  default     = 1
  description = "Initial desired task count. Service lifecycle ignores changes to this after first apply."
}

variable "command" {
  type        = list(string)
  default     = []
  description = "Container command (overrides image CMD). Empty = use image default."
}

variable "expose_via_alb" {
  type        = bool
  default     = false
  description = "If true, creates a Target Group + Listener Rule on the ALB and wires the service load balancer. If false, task runs headless (worker pattern)."
}

variable "host" {
  type        = string
  default     = null
  description = "Host header used to route traffic on the shared ALB listener. Required when expose_via_alb=true."
}

variable "container_port" {
  type        = number
  default     = 0
  description = "Port the container listens on. Required when expose_via_alb=true."
}

variable "alb_listener_arn" {
  type        = string
  default     = null
  description = "ARN of the shared ALB HTTP listener to attach the rule to. Required when expose_via_alb=true."
}

variable "alb_security_group_id" {
  type        = string
  default     = null
  description = "Security group ID of the shared ALB (task SG ingress is allowed from this SG). Required when expose_via_alb=true."
}

variable "listener_rule_priority" {
  type        = number
  default     = null
  description = "Priority for the ALB listener rule (1-50000). Must be unique per listener across apps. Required when expose_via_alb=true."
}

variable "health_check_path" {
  type        = string
  default     = "/"
  description = "Path used by ALB target group health check."
}

variable "health_check_matcher" {
  type        = string
  default     = "200-299"
  description = "HTTP status codes considered healthy."
}

variable "log_retention_days" {
  type        = number
  default     = 14
  description = "CloudWatch log group retention in days."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource created by this module."
}
