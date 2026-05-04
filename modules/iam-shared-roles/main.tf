# Shared IAM roles for ECS task execution and tasks.
# Uma única exec role e uma única tasks role, compartilhadas entre todos os
# services do nix_webserver (web, beat, worker-high, worker-low, worker-agent).

# ===== Execution Role =====
# Usada pelo agente ECS (Fargate) durante o startup do container:
# - Pull de imagem no ECR
# - Escrita de logs no CloudWatch
# Não é a role do código da aplicação (essa é a tasks role).

data "aws_iam_policy_document" "exec_assume" {
  statement {
    sid     = "ECSTaskExecutionAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "exec_inline" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECR"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "exec" {
  name               = "${var.name_prefix}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.exec_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "exec_inline" {
  name   = "${aws_iam_role.exec.name}-inline"
  role   = aws_iam_role.exec.id
  policy = data.aws_iam_policy_document.exec_inline.json
}

# ===== Tasks Role =====
# Assumida pelo código da aplicação rodando dentro do container.
# Sem permissões por padrão — adicionar policies adicionais via
# aws_iam_role_policy_attachment ou aws_iam_role_policy fora deste módulo.
#
# Condições no trust = proteção contra confused-deputy: garantem que
# só ECS desta conta E desta região consegue assumir.

data "aws_iam_policy_document" "task_assume" {
  statement {
    sid     = "ECSTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${var.region}:${var.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
  tags               = var.tags
}

# ===== Policies adicionais (opcionais) =====
# Suporte a anexar policies extras nas duas roles sem precisar modificar o
# módulo. Use managed_policy_arns para AWS-managed/customer-managed e
# inline_policies (map de nome → JSON) para policies inline.

resource "aws_iam_role_policy_attachment" "exec_managed" {
  for_each   = toset(var.exec_managed_policy_arns)
  role       = aws_iam_role.exec.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "exec_extra_inline" {
  for_each = var.exec_inline_policies
  name     = each.key
  role     = aws_iam_role.exec.id
  policy   = each.value
}

resource "aws_iam_role_policy_attachment" "task_managed" {
  for_each   = toset(var.task_managed_policy_arns)
  role       = aws_iam_role.task.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "task_extra_inline" {
  for_each = var.task_inline_policies
  name     = each.key
  role     = aws_iam_role.task.id
  policy   = each.value
}
