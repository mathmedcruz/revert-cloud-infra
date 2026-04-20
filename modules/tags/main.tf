locals {
  default_tags = {
    Application = var.app_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  tags = merge(local.default_tags, var.custom_tags)
}
