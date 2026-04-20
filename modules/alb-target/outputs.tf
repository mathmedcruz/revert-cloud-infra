output "target_group_arn" {
  description = "Target group ARN — passed to the ECS service load_balancer block."
  value       = aws_lb_target_group.this.arn
}

output "target_group_name" {
  value = aws_lb_target_group.this.name
}

output "listener_rule_arn" {
  value = aws_lb_listener_rule.this.arn
}
