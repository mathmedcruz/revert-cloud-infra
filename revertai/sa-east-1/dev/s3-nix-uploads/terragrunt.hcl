terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git//.?ref=v5.12.0"
}

# Bucket de uploads do nix_webserver — armazena mídia dos tenants:
# PDFs de relatórios, planilhas importadas (Addepar, XP, BTG), anexos.
#
# Estrutura de chaves (montada por S3Connector em
# nix_webserver/connectors/s3_connector/s3_connector.py:34-42):
#   <tenant>/<processing_stage>/<file_model>/<reference_date>/<file_name>
# Ex.: ekho/raw/positionsdailyreport/2026-04-30/foo.json
#
# Acesso 100% privado:
# - Sem hosting de website estático (não é portal)
# - Sem CORS público (acesso só do task role do nix via SDK boto3)
# - block_public_access ON
# - boto3 dentro das tasks ECS usa task role (metadata endpoint), sem AWS_ACCESS_KEY

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  environment      = local.environment_vars.locals.environment

  bucket_name = "rvt-${local.environment}-nix-uploads"
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
  bucket = local.bucket_name

  # Acesso público bloqueado — bucket é privado, acessado só via SDK com IAM.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Bucket owner controla todos os objetos (sem ACLs do uploader).
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  # Versioning ON: rollback de arquivo se upload corrompido sobrescrever objeto.
  versioning = {
    enabled = true
  }

  # SSE-S3 (AES256) — sem custo extra, suficiente pra dev.
  # Em prod considerar KMS CMK (audit trail por kms:Decrypt).
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # Sem CORS — bucket NÃO é acessado via browser cross-origin.
  # Quando o portal precisar baixar um arquivo, o nix gera presigned URL via
  # S3Connector.get_file_url() (s3_connector.py:114-141). Browser baixa
  # do CloudFront-equivalente automatico do S3 (signed URL não usa CORS).
  cors_rule = []

  # Lifecycle:
  # - Versões antigas expiram após 90 dias (rollback window suficiente p/ uploads de tenant)
  # - Multipart uploads abandonados limpos após 7 dias (custo + lixo)
  lifecycle_rule = [
    {
      id      = "expire-noncurrent-versions"
      enabled = true
      noncurrent_version_expiration = {
        noncurrent_days = 90
      }
    },
    {
      id                                     = "abort-incomplete-multipart"
      enabled                                = true
      abort_incomplete_multipart_upload_days = 7
    },
  ]

  # AJUSTE: dev permite delete + recreate fácil. Em prod, force_destroy = false
  # (e evitar destroy do bucket — perda de dados de tenant é crítica).
  force_destroy = true

  tags = dependency.tags.outputs.tags
}
