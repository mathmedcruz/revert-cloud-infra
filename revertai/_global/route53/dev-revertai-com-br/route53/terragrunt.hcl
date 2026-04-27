terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-route53.git//.?ref=v6.4.0"
}

locals {
  commons_vars     = read_terragrunt_config(find_in_parent_folders("commons.hcl"))
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))

  app_name    = local.commons_vars.locals.app_name
  environment = local.environment_vars.locals.environment
  custom_tags = local.environment_vars.locals.custom_tags
  root_domain = local.account_vars.locals.root_domain
  zone_name   = "${local.environment}.${local.root_domain}"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  name    = local.zone_name
  comment = "${local.environment} hosted zone"

  records = {
    exemplo = {

    }
  }

  tags = merge(
    {
      Application = local.app_name
      Environment = local.environment
      ManagedBy   = "Terraform"
    },
    local.custom_tags,
  )
}
