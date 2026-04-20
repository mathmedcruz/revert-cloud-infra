terraform {
  source = "${get_parent_terragrunt_dir()}/modules/tags"
}

locals {
  commons_vars     = read_terragrunt_config(find_in_parent_folders("commons.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  app_name    = local.commons_vars.locals.app_name
  environment = local.environment_vars.locals.environment
  custom_tags = local.environment_vars.locals.custom_tags
}
