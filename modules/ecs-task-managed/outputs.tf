output "task_definition_family" {
  description = "Family da task-def. Workflow registra revisões reais sob esse family."
  value       = aws_ecs_task_definition.bootstrap.family
}

output "bootstrap_task_definition_arn" {
  description = "ARN da revision 1 (bootstrap, vestigial). Não usar pra rodar — workflow registra revisões novas."
  value       = aws_ecs_task_definition.bootstrap.arn
}

output "log_group_name" {
  description = "Nome do CloudWatch Log Group."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN do CloudWatch Log Group."
  value       = aws_cloudwatch_log_group.this.arn
}
