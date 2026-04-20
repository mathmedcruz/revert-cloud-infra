output "ecr_repository_url" {
  description = "URL of the ECR repo — give this to CI as IMAGE destination."
  value       = aws_ecr_repository.this.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repo."
  value       = aws_ecr_repository.this.arn
}

output "service_name" {
  description = "ECS service name — referenced by CI's aws-ecs/update_service."
  value       = module.service.name
}

output "task_definition_family" {
  description = "Task definition family — referenced by CI's aws-ecs/update_task_definition."
  value       = module.service.task_definition_family
}

output "task_security_group_id" {
  description = "Security group ID attached to the task ENIs."
  value       = module.service.security_group_id
}

output "task_role_arn" {
  description = "ARN of the task role — attach app-specific IAM policies here."
  value       = module.service.tasks_iam_role_arn
}

output "task_role_name" {
  description = "Name of the task role."
  value       = module.service.tasks_iam_role_name
}

output "task_exec_role_arn" {
  description = "ARN of the task execution role."
  value       = module.service.task_exec_iam_role_arn
}

output "target_group_arn" {
  description = "Target group ARN (only set when expose_via_alb=true)."
  value       = var.expose_via_alb ? aws_lb_target_group.this[0].arn : null
}
