terraform {
  source = "${get_parent_terragrunt_dir()}/modules/ecs-task-managed"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region

  # Workload one-shot pra import de schema/dump no RDS via aws ecs run-task.
  # Imagem real (com psql + ci_db_dump/schema.sql baked-in) é buildada pelo
  # workflow `db-import.yml` no repo nix_webserver. Bootstrap aqui é busybox
  # (placeholder) — o workflow registra revisão nova com a imagem do build.
  task_family    = "td-${local.environment}-nix-db-import"
  container      = "nix_db_import"
  log_group_name = "/ecs/${local.environment}/nix-db-import"
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

dependency "iam" {
  config_path = "../iam"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    task_exec_iam_role_arn = "arn:aws:iam::000000000000:role/dummy-exec"
    tasks_iam_role_arn     = "arn:aws:iam::000000000000:role/dummy-task"
  }
}

inputs = {
  family         = local.task_family
  container_name = local.container
  region         = local.region

  task_exec_iam_role_arn = dependency.iam.outputs.task_exec_iam_role_arn
  tasks_iam_role_arn     = dependency.iam.outputs.tasks_iam_role_arn

  log_group_name     = local.log_group_name
  log_retention_days = 30

  tags = dependency.tags.outputs.tags
}
