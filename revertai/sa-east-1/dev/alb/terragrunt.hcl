terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-alb.git//.?ref=v9.11.0"
}

locals {
  commons_vars     = read_terragrunt_config(find_in_parent_folders("commons.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))

  app_name    = local.commons_vars.locals.app_name
  environment = local.environment_vars.locals.environment

  # Certificado ACM criado manualmente na console (sa-east-1).
  # Cobre 2 níveis simultâneos:
  # - *.dev.revertai.com.br        (apex tenant, python-app, app, etc.)
  # - *.api.dev.revertai.com.br    (wildcard tenant do nix_webserver multi-tenant)
  # Validação DNS via Route53 na zone `dev.revertai.com.br`.
  # ACM auto-renova enquanto os CNAMEs de validação continuarem na zone.
  acm_cert_arn = "arn:aws:acm:sa-east-1:175209828699:certificate/125d64e4-1160-4815-b87c-0f7c1212a008"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs_merge_with_state           = true
  mock_outputs = {
    vpc_id         = "vpc-00000000"
    public_subnets = ["subnet-00000000", "subnet-00000001", "subnet-00000002"]
  }
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
  name    = "${local.app_name}-${local.environment}"
  vpc_id  = dependency.vpc.outputs.vpc_id
  subnets = dependency.vpc.outputs.public_subnets

  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTP from anywhere (redirected to HTTPS)"
    }
    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTPS from anywhere"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  # HTTP listener apenas redireciona para HTTPS (301).
  # HTTPS é onde as apps registram suas listener rules — default action = fixed 404
  # quando nenhuma rule (host_header) bate.
  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    https = {
      port            = 443
      protocol        = "HTTPS"
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      certificate_arn = local.acm_cert_arn
      fixed_response = {
        content_type = "text/plain"
        message_body = "404 Not Found"
        status_code  = "404"
      }
    }
  }

  # No target groups created here. Each app in apps/<name>/ creates its own TG
  # and listener rule via the local module (modules/app/).
  target_groups = {}

  tags = dependency.tags.outputs.tags
}
