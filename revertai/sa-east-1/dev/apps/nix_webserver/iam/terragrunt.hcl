terraform {
  source = "${get_parent_terragrunt_dir()}/modules/iam-shared-roles"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  account_vars     = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region
  account_id  = local.account_vars.locals.account_number
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
  # 'dev-nix' → 'dev-nix-ecs-exec' / 'dev-nix-ecs-task'.
  name_prefix = "${local.environment}-nix"
  account_id  = local.account_id
  region      = local.region
  tags        = dependency.tags.outputs.tags

  # ==========================================================================
  # Execution role (dev-nix-ecs-exec): usada pelo agente ECS pra puxar imagem
  # do ECR, escrever logs no CloudWatch e injetar secrets via valueFrom.
  # ==========================================================================
  exec_managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonSSMFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
  ]

  # ==========================================================================
  # Tasks role (dev-nix-ecs-task): assumida pelo código da aplicação.
  # ==========================================================================
  task_managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMFullAccess",
  ]

  # Inline policies anexadas à tasks role.
  # ECSExecPolicy: requerida pra `aws ecs execute-command` (shell interativo
  # via SSM Session Manager) — `ssmmessages:*` abre o canal control/data
  # entre o agente SSM dentro do container e o serviço SSM. Bloco `logs:*`
  # cobre o caso do cluster ter executeCommandConfiguration.logging habilitado.
  task_inline_policies = {
    ECSExecPolicy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "logs:DescribeLogGroups",
            "logs:CreateLogStream",
            "logs:DescribeLogStreams",
            "logs:PutLogEvents",
          ]
          Resource = "*"
        },
      ]
    })
  }
}
