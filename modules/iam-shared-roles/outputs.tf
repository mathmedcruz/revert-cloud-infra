output "task_exec_iam_role_arn" {
  description = "ARN da execution role compartilhada (referenciada pelos services ECS via task_exec_iam_role_arn)."
  value       = aws_iam_role.exec.arn
}

output "task_exec_iam_role_name" {
  description = "Nome da execution role compartilhada."
  value       = aws_iam_role.exec.name
}

output "tasks_iam_role_arn" {
  description = "ARN da tasks role compartilhada (assumida pelo código da aplicação)."
  value       = aws_iam_role.task.arn
}

output "tasks_iam_role_name" {
  description = "Nome da tasks role compartilhada."
  value       = aws_iam_role.task.name
}
