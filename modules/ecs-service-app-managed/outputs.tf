output "service_name" {
  description = "Nome do ECS service criado."
  value       = module.service.name
}

output "service_id" {
  description = "ID do ECS service (igual ao name pra Fargate)."
  value       = module.service.id
}

output "task_definition_family" {
  description = "Family da task-def. CI registra revisions sob esse family."
  value       = aws_ecs_task_definition.bootstrap.family
}

output "bootstrap_task_definition_arn" {
  description = "ARN da revision 1 (bootstrap, fóssil). Não usar pra deploy — CI mantém revisions reais."
  value       = aws_ecs_task_definition.bootstrap.arn
}

output "security_group_id" {
  description = "ID do SG criado pra essa task."
  value       = module.service.security_group_id
}
