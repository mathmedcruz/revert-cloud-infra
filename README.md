# revert-cloud-infra

Infraestrutura AWS gerenciada com **Terragrunt** + **OpenTofu**. Define VPC, ECS Fargate cluster, ALB compartilhado, ECR e serviços de aplicação na conta dev.

---

## Stack

| Ferramenta | Versão | Por quê |
|---|---|---|
| Terragrunt | `1.0.1` | Orquestração e DRY de configs |
| OpenTofu | `1.11.6` | Engine (fork open-source do Terraform) |
| Backend | S3 + lockfile nativo | Lock via `use_lockfile = true` (Terraform ≥ 1.10) — sem DynamoDB |

Versões fixadas no workflow `.github/workflows/terragrunt-{plan,apply}.yml`.

---

## Estrutura do repositório

```
.
├── commons.hcl                 # variáveis globais (app_name)
├── root.hcl                    # backend S3, provider, retry_lock, auto_approve
├── modules/                    # módulos locais reutilizáveis
│   ├── tags/                   # convenção de tags padrão (Environment, App, ManagedBy)
│   ├── ecr/                    # ECR repository + lifecycle policy
│   └── alb-target/             # target group + listener rule (host_header) p/ apps no listener HTTPS
├── revertai/                   # account "revertai"
│   ├── account.hcl             # account_number = get_aws_account_id(), root_domain
│   ├── _global/                # serviços AWS region-agnostic (Route53)
│   │   ├── region.hcl          # pinado em sa-east-1 (state bucket compartilhado)
│   │   └── route53/dev-revertai-com-br/
│   │       ├── environment.hcl
│   │       └── route53/        # hosted zone "dev.revertai.com.br"
│   └── sa-east-1/              # região
│       ├── region.hcl          # region = "sa-east-1"
│       └── dev/                # environment
│           ├── environment.hcl # environment, vpc_cidr, custom_tags
│           ├── tags/           # módulo tags (compartilhado pelo env)
│           ├── vpc/            # terraform-aws-modules/vpc v5.21.0
│           ├── ecs-cluster/    # terraform-aws-modules/ecs/cluster v7.5.0 + service_connect_defaults
│           ├── cloudmap/       # aws_service_discovery_http_namespace (rvt-<env>.local) p/ Service Connect
│           ├── alb/            # terraform-aws-modules/alb v9.11.0
│           └── apps/
│               └── example/    # aplicação de exemplo
│                   ├── ecr/
│                   ├── alb-target/
│                   ├── dns/      # record A/ALIAS na hosted zone → ALB
│                   └── service/  # terraform-aws-modules/ecs/service v7.5.0
└── .github/workflows/
    ├── terragrunt-plan.yml     # roda em PR pra main
    ├── terragrunt-apply.yml    # roda em push pra main (após merge)
    └── test-oidc.yml           # smoke test do OIDC
```

### Hierarquia de configs (HCL)

`root.hcl` carrega automaticamente os arquivos por nível usando `find_in_parent_folders`:

```
commons.hcl  → app_name
account.hcl  → account_number
region.hcl   → region
environment.hcl → environment, vpc_cidr, custom_tags
```

Adicionar um novo ambiente é criar `revertai/sa-east-1/<env>/environment.hcl` + os units (vpc, ecs-cluster, etc.). Adicionar uma nova região é criar `revertai/<region>/region.hcl`.

---

## Backend remoto

Definido em `root.hcl`. Cada module guarda state em:

```
s3://<ACCOUNT_ID>-<region>-terraform-remote-state/<app_name>/<path-relative-to-root>/terraform.tfstate
```

- **Encryption:** SSE-S3 (`encrypt = true`)
- **Versioning:** ativado no bucket (manual)
- **Locking:** `use_lockfile = true` — lock nativo do S3 (sem DynamoDB)
- **Provider:** AWS provider gerado dinamicamente pra região do unit (`provider.tf` injetado pelo `root.hcl`)

`extra_arguments` no `root.hcl`:
- `retry_lock` → `-lock-timeout=20m` em comandos com lock
- `auto_approve` → `-auto-approve` em `apply` (necessário pro CI)
- `fix-log-output` → `-no-color` em comandos com vars (output limpo nos logs do GitHub)

---

## Módulos em uso

| Unit | Source | O que cria |
|---|---|---|
| `tags` | local (`modules/tags`) | Map de tags com `Environment`, `App`, `ManagedBy=terraform` |
| `vpc` | `terraform-aws-modules/terraform-aws-vpc` v5.21.0 | VPC, 3 subnets públicas + 3 privadas em 3 AZs, NAT gateway único, IGW, route tables |
| `ecs-cluster` | `terraform-aws-modules/terraform-aws-ecs/cluster` v7.5.0 | Cluster Fargate (capacity provider FARGATE) + `service_connect_defaults.namespace` herdado de `cloudmap/` |
| `cloudmap` | `aws_service_discovery_http_namespace` (inline no terragrunt) | Namespace `rvt-<env>.local` usado por ECS Service Connect — ver [`docs/service-connect.md`](docs/service-connect.md) |
| `alb` | `terraform-aws-modules/terraform-aws-alb` v9.11.0 | ALB internet-facing. Listener HTTP:80 redireciona 301→HTTPS. Listener HTTPS:443 (TLS 1.3-1.2, cert ACM wildcard `*.dev.revertai.com.br`) com default action `404`. SG com ingress 80+443 em 0.0.0.0/0 |
| `_global/route53/dev-revertai-com-br/route53` | `terraform-aws-modules/terraform-aws-route53` v6.4.0 | Hosted zone pública `dev.revertai.com.br` |
| `apps/example/ecr` | local (`modules/ecr`) | ECR repository + lifecycle policy |
| `apps/example/alb-target` | local (`modules/alb-target`) | Target group + listener rule (`host_header` derivado de `account.hcl` + `environment.hcl`) anexada ao **listener HTTPS:443** do ALB |
| `apps/example/dns` | `terraform-aws-modules/terraform-aws-route53` v6.4.0 (raiz, `create_zone = false`) | Record A/ALIAS apontando o subdomínio da app pro ALB |
| `apps/example/service` | `terraform-aws-modules/terraform-aws-ecs/service` v7.5.0 | ECS service Fargate, task definition (1 container nginx:alpine bootstrap), task role + execution role IAM, SG, log group |

### Padrão de "app"

Cada aplicação vive em `revertai/<region>/<env>/apps/<app-name>/` com 4 units:

1. `ecr/` — repositório de imagem
2. `alb-target/` — target group + regra de roteamento no ALB compartilhado (`host_header`)
3. `dns/` — record A/ALIAS no Route53 pra resolver `<sub>.<env>.<root_domain>` → ALB
4. `service/` — ECS service + task definition

**Invariante crítica:** o subdomínio em `dns/` (`app_subdomain`) e o em `alb-target/` (`app_host`) precisam casar. Se divergirem, a query DNS resolve mas o ALB cai na fixed-response 404 do listener (host_header não bate).

**TLS termina no ALB.** O cert ACM wildcard cobre `*.dev.revertai.com.br` — qualquer app nova herda HTTPS sem mudança no código da app. Tráfego ALB → task continua HTTP:80 (rede privada, dentro da VPC). Container expõe HTTP normalmente; não precisa lidar com TLS.

A task definition é só um **bootstrap** (nginx:alpine). CI/CD da aplicação atualiza a task definition em runtime — `ignore_task_definition_changes = true` no terragrunt previne reverter.

### Comunicação service-to-service (ECS Service Connect)

Pra services dentro do mesmo cluster que conversam entre si (ex.: workers chamando uma API interna), o padrão é **ECS Service Connect** com namespace HTTP do Cloud Map (`rvt-<env>.local`). Cada service ECS opta-in via `service_connect_configuration` no terragrunt:

- **Server** (publica alias): declara `service[]` com `port_name`, `discovery_name`, `client_alias`. Apps remotas resolvem via `http://<alias>.rvt-<env>.local:<porta>`.
- **Client** (só consome): basta `{ enabled = true }`. ECS injeta envoy sidecar que intercepta chamadas via iptables.

O cluster ECS herda o namespace default de `cloudmap/` (`service_connect_defaults`), então services não precisam declarar `namespace` individualmente. Detalhes completos (data plane, troubleshooting, migração de Cloud Map clássico) em [`docs/service-connect.md`](docs/service-connect.md).

---

## Mock outputs em dependências

Todos os `dependency` blocks têm `mock_outputs` pra que `terragrunt run --all plan` rode antes do primeiro apply. Os mocks são usados quando o state remoto da dependência ainda não existe; depois do primeiro apply, `mock_outputs_merge_with_state = true` faz os outputs reais sobrescreverem os mocks.

**Pegadinha conhecida:** o módulo `terraform-aws-modules/ecs/service` faz `data "aws_subnet"` — query real à API AWS — com os subnet IDs vindos do mock. Como `subnet-00000000` não existe, o plan do `service` falha **no primeiro plan, antes de qualquer apply**. Solução: bootstrap manual em ordem (ver abaixo).

---

## CI/CD

Dois workflows separados — `plan` em PR, `apply` em merge.

### `terragrunt-plan.yml`
- **Trigger:** `pull_request` em `main` + `workflow_dispatch`
- **Permissions:** `id-token: write`, `contents: read`, `pull-requests: write`
- **Comando:** `terragrunt run --all plan --non-interactive` em `revertai/sa-east-1/dev`
- **PR comment:** `tg_comment: '1'` (action posta o plan no PR)

### `terragrunt-apply.yml`
- **Trigger:** `push` em `main` + `workflow_dispatch`
- **Concurrency:** `terragrunt-apply-dev` com `cancel-in-progress: false` (nunca cancela apply em andamento)
- **Environment:** `dev` — required reviewers no GitHub Environment exigem aprovação humana antes do job rodar
- **Comando:** `terragrunt run --all apply --non-interactive`

### Autenticação AWS

OIDC via `aws-actions/configure-aws-credentials@v4`. Sem chave de acesso longa.

- **Variável de repo (Settings → Variables):** `AWS_ROLE_ARN` — ARN do role IAM que o GitHub Actions assume
- **Token:** `secrets.GITHUB_TOKEN` é gerado automaticamente pelo Actions (não precisa criar)

---

## Setup AWS (uma vez por conta)

### 1. OIDC provider

Criar provider OIDC pra `token.actions.githubusercontent.com` na conta AWS:
- URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

### 2. Role do GitHub Actions

Trust policy permite o OIDC provider, condicionada ao repositório. Padrão recomendado quando se quer separar plan/apply: dois roles distintos com `sub` diferente. Configuração atual usa **um role só** (`github-actions-oidc`) com trust permitindo PR + push em main.

Permissions policy do role contém:
- Acesso ao bucket de state (`s3:Get/Put/Delete/List` em `<ACCOUNT_ID>-sa-east-1-terraform-remote-state`)
- Permissões de write nos serviços usados pelos módulos: `ec2:*`, `ecs:*`, `elasticloadbalancing:*`, `ecr:*`, `logs:*`, `autoscaling:*`, `application-autoscaling:*`, IAM completo (Create/Delete/Get/List/Tag/PassRole/etc.), `tag:Tag/Untag/Get*`
- Route53: `Get*`/`List*` em `hostedzone/*` (todas as zones), write actions só em `hostedzone/Z02162213D9FQ8K2T15KD` (zone `dev.revertai.com.br`), `route53:GetChange` em `change/*`
- ACM: **não precisa** — o cert é referenciado pelo ARN como string opaca; o role não cria/deleta certs (gestão manual no console)

### 3. Permissions boundary (`terragrunt-pipeline-boundary`)

Customer-managed policy aplicada como **permissions boundary** nos roles que o terraform cria (task role e execution role do ECS service). **Não** aplicada no role do CI — boundary no CI bloquearia o próprio CI de criar roles.

Statements de Deny da boundary:
- `iam:*` — impede privilege escalation via IAM
- Account/billing/support/organizations — fora do escopo de runtime de aplicação
- Tampering em CloudTrail/Config/GuardDuty/SecurityHub — impede atacante de apagar logs de atividade
- Admin de VPC/subnet/IGW/NAT — blast radius muito alto

Aplicada via inputs do terragrunt no `apps/example/service/terragrunt.hcl`:

```hcl
inputs = {
  tasks_iam_role_permissions_boundary     = "arn:aws:iam::<ACCOUNT_ID>:policy/terragrunt-pipeline-boundary"
  task_exec_iam_role_permissions_boundary = "arn:aws:iam::<ACCOUNT_ID>:policy/terragrunt-pipeline-boundary"
}
```

### 4. GitHub Environment `dev`

`Settings → Environments → New environment → "dev"`:
- **Required reviewers** — pra forçar aprovação manual antes de cada apply
- **Deployment branches** — `Selected branches: main`

### 5. Variable de repo

`Settings → Secrets and variables → Actions → Variables`:
- `AWS_ROLE_ARN` = ARN do role criado no passo 2

### 6. Certificado ACM (manual, não IaC)

Cert wildcard pra todas as apps em dev. Criado **uma vez** no console da AWS, gerenciado fora do terraform.

1. Console AWS → **ACM** → região **sa-east-1** (importante: precisa ser a mesma do ALB)
2. `Request a certificate` → `Public certificate`
3. **Domain names:**
   - `*.dev.revertai.com.br` (cobre todas as apps)
   - `dev.revertai.com.br` (apex, opcional)
4. **Validation method:** `DNS validation`
5. Após criar, em **Domains**: clicar `Create records in Route 53` para cada nome (cria os CNAMEs de validação automaticamente)
6. Aguardar status `Issued` (~5–30 min)
7. Copiar o ARN e atualizar `local.acm_cert_arn` em `revertai/sa-east-1/dev/alb/terragrunt.hcl`

O ARN do cert é referenciado como string opaca pelo ALB. O role do CI **não precisa** de permissões ACM.

Renovação: ACM renova automaticamente certs validados via DNS — sem intervenção.

---

## Bootstrap (primeiro deploy)

Devido ao `data "aws_subnet"` no módulo upstream do ECS service, **`run --all plan` falha antes do primeiro apply**. Solução: aplicar manualmente em ordem de dependência uma vez.

**Pré-requisito:** cert ACM já criado no console (ver "Setup AWS → 6. Certificado ACM"). Sem o cert, `apply` do `alb` falha.

```bash
cd revertai/sa-east-1/dev

# Ordem importa: tags antes de quem consome tags;
# vpc antes de quem consome subnet/sg; etc.
terragrunt apply -auto-approve --working-dir tags
terragrunt apply -auto-approve --working-dir vpc
terragrunt apply -auto-approve --working-dir ecs-cluster
terragrunt apply -auto-approve --working-dir alb         # consome cert ACM (string ARN em local.acm_cert_arn)
terragrunt apply -auto-approve --working-dir apps/example/ecr
terragrunt apply -auto-approve --working-dir apps/example/alb-target
terragrunt apply -auto-approve --working-dir apps/example/service
terragrunt apply -auto-approve --working-dir apps/example/dns

# Hosted zone fica em _global (rodar separadamente, antes do dns/ da app)
cd ../../_global/route53/dev-revertai-com-br
terragrunt apply -auto-approve --working-dir route53
```

Depois desse bootstrap, `run --all plan` no PR funciona porque os outputs reais do state sobrescrevem os mocks.

---

## Fluxo de trabalho

### Mudança normal

1. Branch a partir de `main`
2. Mexer nos `terragrunt.hcl` ou em `modules/`
3. Abrir PR pra `main`
4. **Plan** roda no PR e é postado como comentário
5. Revisar plan + diff de código
6. Merge → **apply** dispara em `main`
7. GitHub Environment `dev` pausa esperando aprovação
8. Aprovar → apply executa

### Adicionar uma nova app

Os 4 units de `apps/example/` têm comentários `# AJUSTE:` em cada ponto que precisa mudar pra uma nova app. Workflow:

1. **Copiar a pasta:**
   ```bash
   cp -r revertai/sa-east-1/dev/apps/example revertai/sa-east-1/dev/apps/<nova-app>
   ```

2. **Buscar e ajustar todos os `# AJUSTE:`** (em VS Code: `Ctrl+Shift+F` por `# AJUSTE:`):

   | Arquivo | O que mudar |
   |---|---|
   | `dns/terragrunt.hcl` | `app_subdomain` — subdomínio público |
   | `alb-target/terragrunt.hcl` | `app_host` (subdomínio DEVE bater com `app_subdomain` do dns), `name` (target group), `listener_rule_priority` (único no ALB — incrementar +10), `health_check_path` |
   | `ecr/terragrunt.hcl` | `name` do repo ECR |
   | `service/terragrunt.hcl` | locals (`service_name`, `task_family`, `container`, `log_group` — trocar `"example"` pelo nome da app), `cpu`/`memory`/`desired_count`, `image` (bootstrap), porta nos `portMappings` (precisa casar com `container_port` do alb-target) |

3. **Bootstrap manual** (primeira vez — `run --all plan` falha por causa do mock de subnets):
   ```bash
   cd revertai/sa-east-1/dev
   terragrunt apply -auto-approve --working-dir apps/<nova-app>/ecr
   terragrunt apply -auto-approve --working-dir apps/<nova-app>/alb-target
   terragrunt apply -auto-approve --working-dir apps/<nova-app>/service
   terragrunt apply -auto-approve --working-dir apps/<nova-app>/dns
   ```

4. **PR + merge** — runs futuros vão pelo CI (`plan` no PR, `apply` no merge).

**Checklist final** antes de abrir o PR:
- [ ] Subdomínio idêntico em `dns/` e `alb-target/`
- [ ] `listener_rule_priority` único entre todas as apps existentes
- [ ] Porta do `service` (portMappings) bate com `container_port` do `alb-target`
- [ ] Nome do repo ECR já tem imagem buildada (senão a CI da app vai falhar no primeiro deploy)

**HTTPS é automático**: o cert ACM wildcard `*.dev.revertai.com.br` cobre qualquer subdomínio novo. Não precisa criar/renovar/anexar cert por app — só garantir que o `app_subdomain` está em 1 nível abaixo de `dev.revertai.com.br`.

### Adicionar um novo recurso que cria role IAM

Sempre passar a boundary nos inputs do módulo (ex: `*_permissions_boundary`). A regra: **se o `plan` do unit lista `aws_iam_role`, ele precisa de boundary**.

---

## Convenções

- **Naming:** `<app_name>-<environment>` no nível de infra compartilhada (vpc, alb, cluster); `<environment>-<app>` em apps específicas (ecr, alb-target)
- **Tags:** sempre via `dependency.tags.outputs.tags` — não definir tags ad-hoc nos units
- **Versões de módulo:** sempre fixadas via `?ref=vX.Y.Z` no `source` (sem `latest`/`HEAD`)
- **Variáveis sensíveis:** **não** usar — toda config é não-sensível e pode estar versionada. Segredos de aplicação ficam em SSM/Secrets Manager (assumidos via task role)
