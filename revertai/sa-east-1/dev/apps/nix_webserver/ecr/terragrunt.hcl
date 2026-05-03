terraform {
  source = "${get_parent_terragrunt_dir()}/modules/ecr"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  environment      = local.environment_vars.locals.environment
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "tags" {
  config_path = "../../../tags"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    tags = {}
  }
}

inputs = {
  # Repo único compartilhado pelos 5 services (web + 3 workers + beat).
  # A diferença entre eles é o `command` no task-def, não a imagem.
  name = "${local.environment}-nix_webserver"

  tags = dependency.tags.outputs.tags
}
