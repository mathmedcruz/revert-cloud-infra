terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git//.?ref=v5.21.0"
}

locals {
  commons_vars     = read_terragrunt_config(find_in_parent_folders("commons.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))

  app_name    = local.commons_vars.locals.app_name
  environment = local.environment_vars.locals.environment
  vpc_cidr    = local.environment_vars.locals.vpc_cidr
  region      = local.region_vars.locals.region

  azs = [
    "${local.region}a",
    "${local.region}b",
    "${local.region}c",
  ]
}


include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "tags" {
  config_path = "../tags"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    tags = {}
  }
}

inputs = {
  name = "${local.app_name}-${local.environment}"
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = dependency.tags.outputs.tags
}
