# ECS Service Connect

Comunicação service-to-service entre tasks no mesmo cluster ECS, gerenciada pela AWS via Envoy sidecar injetado automaticamente. Substitui Cloud Map "clássico" (DNS via Route53), ALB interno, e App Mesh self-managed em casos onde os services conversam dentro do mesmo cluster.

Esse doc explica o que Service Connect é, como está configurado no `revert-cloud-infra`, e como adicionar/manter para novos services.

---

## TL;DR

- **O que é**: AWS injeta um Envoy sidecar em cada task. Tráfego do app pra `<alias>.<namespace>` é interceptado por iptables, balanceado e roteado pelo envoy. Sem DNS clássico, sem instalação de mesh.
- **Onde vive no repo**: `revertai/<region>/<env>/cloudmap/` (namespace) + `revertai/<region>/<env>/ecs-cluster/` (default cluster namespace) + flag `service_connect_configuration` no terragrunt de cada service.
- **Custo**: ~$0 de infra (HTTP namespace). Cada task ganha ~256 MiB + 50 mCPU pro envoy sidecar — pago dentro do sizing da task.
- **Estado atual (dev)**: 1 server (`evolution-api`), 5 clients (web + 3 workers + beat).

---

## 1. Mental model

> Cada task ganha um proxy **Envoy** local. Chamadas pra `evolution-api.rvt-dev.local:8080` viram tráfego HTTP/TCP interceptado por **iptables**, balanceado entre tasks vivas via catálogo em memória (atualizado pelo ECS Agent), com métricas L7 gratuitas no CloudWatch.

Cloud Map **não é alternativa** ao Service Connect. SC **exige** um Cloud Map namespace por baixo (HTTP ou Private DNS) como catálogo de metadados. O nome "Cloud Map" no infra antigo era a feature *standalone* de service discovery via DNS — agora ela vira "estilo clássico".

### Service Connect vs Cloud Map clássico

| Aspecto | Service Connect | Cloud Map clássico |
|---|---|---|
| Quem resolve o hostname | Envoy sidecar (catálogo em memória) | `getaddrinfo` → Route53 Private Hosted Zone |
| Stale endpoints | ~segundos (push) | até TTL (default 60s+) |
| Métricas L7 (status code, latência) | Free no CloudWatch | Não tem |
| Health checking de upstream | Envoy ativo + ECS task health | Só via Route53 health checks (extra) |
| Retries automáticos | Sim | Não (cliente faz) |
| Custo de namespace | $0 (HTTP) ou $0.50/mês (Priv DNS) | $0.50/mês (Priv DNS obrigatório) |
| Overhead por task | +256 MiB + ~50 mCPU (envoy) | $0 |
| Configuração | Single `service_connect_configuration` block | `aws_service_discovery_service` + `service_registries[]` |

Pra **comunicação intra-cluster** (caso nix_webserver), SC ganha em todos os critérios exceto overhead — e o overhead é absorvido facilmente pelo Fargate sizing.

---

## 2. Arquitetura no dev

```
┌──────────────────────────────────────────────────────────────────────┐
│  ECS Cluster: nix-dev                                                │
│  service_connect_defaults.namespace = arn:aws:.../rvt-dev.local      │
│                                                                      │
│  ┌──────────────────────────┐  ┌──────────────────────────────────┐  │
│  │ svc-dev-nix_webserver-web│  │ svc-dev-nix-evolution-api        │  │
│  │   (CLIENT)               │  │   (SERVER + CLIENT)              │  │
│  │                          │  │                                  │  │
│  │  ┌──────────────────┐    │  │  ┌──────────────────┐            │  │
│  │  │ nix_webserver_web│    │  │  │ evolution_api    │            │  │
│  │  │  django  :8000   │    │  │  │   node  :8080    │            │  │
│  │  └────────┬─────────┘    │  │  └────────┬─────────┘            │  │
│  │           │ http://      │  │           │                      │  │
│  │           │ evolution-api│  │           │                      │  │
│  │           │ .rvt-dev     │  │           │                      │  │
│  │           │ .local:8080  │  │           │                      │  │
│  │           ▼              │  │           ▼                      │  │
│  │  ┌──────────────────┐    │  │  ┌──────────────────┐            │  │
│  │  │ envoy sidecar    │────┼──┼──┤ envoy sidecar    │ ← inbound  │  │
│  │  │  (iptables hook) │    │  │  │  (publica :8080) │   listener │  │
│  │  └──────────────────┘    │  │  └──────────────────┘            │  │
│  └──────────────────────────┘  └──────────────────────────────────┘  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Services do dev** (`revertai/sa-east-1/dev/apps/nix_webserver/`):

| Service | Papel SC | Onde |
|---|---|---|
| `service-evolution-api` | **server** (publica `evolution-api:8080`) | `service-evolution-api/terragrunt.hcl` |
| `service-web` | client | `service-web/terragrunt.hcl` |
| `service-worker-low` | client | `service-worker-low/terragrunt.hcl` |
| `service-worker-high` | client | `service-worker-high/terragrunt.hcl` |
| `service-worker-agent` | client | `service-worker-agent/terragrunt.hcl` |
| `service-beat` | client (não chama evolution na prática) | `service-beat/terragrunt.hcl` |

- **Server** = envoy com listener **inbound** que recebe na porta declarada + envoy outbound (também é client de outros services).
- **Client** = só envoy outbound (intercepta chamadas pra `*.rvt-dev.local`).

---

## 3. Data plane — como funciona por dentro

### 3.1 Injeção do sidecar

Quando o `aws_ecs_service` tem `service_connect_configuration.enabled = true`, na hora de subir uma task o ECS Agent:

1. Lê a task definition normal (do repo `nix_webserver/task-definitions/*.json`).
2. **Mutaciona a task spec** adicionando um container chamado `ecs-service-connect-<revision>` com a imagem `public.ecr.aws/ecs/ecs-service-connect-agent` (Envoy customizado pela AWS).
3. Adiciona `essential: true` no sidecar — se o envoy morre, a task inteira é reiniciada.
4. Configura `dependsOn`: o container do app só inicia depois do envoy estar healthy.
5. Aplica `linuxParameters.capabilities.add = ["NET_ADMIN"]` no sidecar (necessário pra criar regras iptables).

O sidecar **não aparece** no task-def JSON do repo. Você só vê em `aws ecs describe-tasks`.

### 3.2 Bootstrap da rede dentro da task

Como `networkMode: awsvpc` (todos os task-defs do nix_webserver), a task tem **uma ENI única compartilhada por todos os containers via network namespace**. `localhost` é compartilhado.

O envoy, ao subir:

1. Lê config via env vars + chamada à ECS Container Agent API local (link-local `169.254.170.2`).
2. Pega a lista de **upstreams** (services remotos que esse cliente pode chamar) e **downstreams** (próprio container, se for server).
3. Cria listeners Envoy:
   - **Outbound listener**: porta dinâmica (ex.: `15001`). Cada client alias gera um `cluster` Envoy nele.
   - **Inbound listener** (só se server): escuta na porta de redirect, encaminha pra `localhost:<containerPort>`.
4. Executa, com NET_ADMIN, regras tipo:
   ```
   iptables -t nat -A OUTPUT -p tcp -m owner ! --uid-owner <envoy> \
            -d <ip-fake-alias> --dport 8080 -j REDIRECT --to-port 15001
   ```
   O IP fake é um IP da subrede `127.255.0.0/16` que o envoy reserva localmente — **um IP fake por alias remoto**.

### 3.3 Resolução "DNS" do alias

Esse é o trecho que mais confunde. **Não é DNS clássico.**

Quando o Django chama `requests.get("http://evolution-api.rvt-dev.local:8080/...")`:

1. **glibc faz `getaddrinfo("evolution-api.rvt-dev.local")`**.
2. ECS Agent populou `/etc/hosts` da task **antes do container do app subir**, mapeando cada alias remoto pra um IP fake local da `127.255.0.0/16`:
   ```
   127.255.0.1  evolution-api.rvt-dev.local evolution-api
   ```
3. glibc retorna `127.255.0.1`.
4. App abre `TCP 127.255.0.1:8080`.
5. **iptables intercepta** (regra REDIRECT instalada pelo envoy) → vai pra `127.0.0.1:15001` (envoy outbound listener).
6. **Envoy seleciona um endpoint real** entre as tasks vivas de `svc-dev-nix-evolution-api`. Catálogo em memória atualizado por push do ECS Agent local — sem chamada Cloud Map em runtime.
7. Envoy abre TCP pro IP da ENI da task destino (ex.: `10.0.2.34`) na porta inbound do envoy server lá (ex.: `15006`).
8. **Envoy do server** recebe, encaminha pro container local (`localhost:8080`).
9. Resposta volta pelo caminho inverso.

**Insight crítico**: Route53 nunca é consultado. Por isso `cloudmap/terragrunt.hcl` usa `aws_service_discovery_http_namespace`, não `private_dns_namespace`.

### 3.4 Métricas no CloudWatch

O envoy emite automaticamente no namespace `AWS/ECS` com dimensions `ServiceName`, `ClusterName`, `Namespace`, `TargetService`, `DiscoveryName`:

- `RequestCount`
- `ProcessedBytes`
- `TargetResponseTime` (p50/p90/p99)
- `HTTPCode_Target_*Count` (`2XX`, `4XX`, `5XX`)
- `ClientTLSNegotiationErrorCount`

L7 grátis sem instrumentação no cliente — útil pra detectar degradação de upstream sem mexer no app.

---

## 4. Configuração no repo

### 4.1 Pré-requisitos (1x por env)

**Namespace** — `revertai/<region>/<env>/cloudmap/terragrunt.hcl`:

```hcl
inputs = {
  namespace_name = "rvt-${local.environment}.local"  # ex.: rvt-dev.local
  tags           = dependency.tags.outputs.tags
}
```

Cria `aws_service_discovery_http_namespace`. HTTP namespace = $0 + sem zone Route53. Se precisar resolver fora do ECS (Lambda fora da VPC, etc.), trocar pra `aws_service_discovery_private_dns_namespace`.

**Default no cluster** — `revertai/<region>/<env>/ecs-cluster/terragrunt.hcl`:

```hcl
dependency "cloudmap" {
  config_path = "../cloudmap"
}

inputs = {
  service_connect_defaults = {
    namespace = dependency.cloudmap.outputs.namespace_arn
  }
}
```

Com isso, qualquer service no cluster que ligar SC herda esse namespace sem precisar declarar.

### 4.2 Adicionar SC num service novo

Os 3 modos comuns:

**Modo client-only** (consome aliases de outros services, não publica nenhum):

```hcl
# revertai/sa-east-1/dev/apps/<app>/service-<x>/terragrunt.hcl
inputs = {
  service_connect_configuration = {
    enabled = true
  }
  # ... resto
}
```

Sidecar é injetado, listeners outbound configurados pra todos os aliases publicados no namespace. Use quando o service consome outros mas não é destino.

**Modo server** (publica um alias):

```hcl
inputs = {
  service_connect_configuration = {
    enabled = true
    service = [{
      port_name      = "evolution-api-8080"   # bate com portMappings[].name na task-def
      discovery_name = "evolution-api"        # nome do service no Cloud Map
      client_alias = {
        port     = 8080
        dns_name = "evolution-api"            # forma evolution-api.rvt-<env>.local
      }
    }]
  }
}
```

**Atenção ao schema**: `client_alias` é **objeto**, não lista. O módulo `terraform-aws-modules/ecs//modules/service` v7.5.0 aceita só um alias por porta. Passar `[{...}]` falha com `attribute "client_alias": object required, but have tuple`.

**Modo SC desligado**:

```hcl
inputs = {
  service_connect_configuration = {}   # ou simplesmente omitir
}
```

Default. Sidecar não é injetado.

### 4.3 Task definition — campos obrigatórios

Pra ser **server**, o `containerDefinitions[].portMappings[]` precisa ter `name`:

```json
"portMappings": [{
  "containerPort": 8080,
  "hostPort": 8080,
  "protocol": "tcp",
  "name": "evolution-api-8080",       // ← obrigatório, referenciado pelo terragrunt
  "appProtocol": "http"                // ← opcional mas habilita métricas L7 corretas
}]
```

O `name` precisa bater **caractere por caractere** com `port_name` no terragrunt. Se não bater, ECS aceita a config mas **não publica o alias** — falha silenciosa.

**Convenção**: `<discovery-name>-<port>` (ex.: `evolution-api-8080`). Lê fácil em logs, escala pra múltiplas portas no mesmo container.

### 4.4 Health checks (recomendado pra servers)

Sem `containerDefinitions[].healthCheck`, ECS sabe que o processo está rodando mas não sabe se a app responde. SC continua roteando pra task com app travado.

**Para o evolution-api** (server único atual):

```json
"healthCheck": {
  "command": ["CMD-SHELL", "node -e \"require('http').get('http://127.0.0.1:8080/',r=>process.exit(r.statusCode<500?0:1)).on('error',()=>process.exit(1))\""],
  "interval": 30,
  "timeout": 5,
  "retries": 3,
  "startPeriod": 60
}
```

Decisões:
- **`node -e`** em vez de `curl`/`wget`: o image Alpine não vem com curl por padrão. Node tá garantido por ser app Node.
- **`127.0.0.1`** em vez de `localhost`: zero dependência de `/etc/hosts` (que o ECS manipula pra SC).
- **`statusCode < 500`** = healthy: 4xx significa "servidor vivo, request errada" — não marcar UNHEALTHY. Só 5xx (erro do servidor) derruba.
- **`startPeriod: 60`**: grace period inicial. Subir DB connection, Redis, providers WhatsApp leva ~30-50s.
- **`retries: 3 × interval: 30`**: ~90s pra detectar morte após startup.

Efeito: task UNHEALTHY → ECS desregistra do Cloud Map → envoys dos clients atualizam catálogo → param de rotear → task killed e recriada.

### 4.5 Apps consumindo aliases (no nix_webserver)

Apps Django/Celery/Node leem URLs do secret `${NIX_SECRET_ARN}` ou equivalente. Pra service connect, o valor do secret deve apontar pro alias completo:

```
EVOLUTION_API_URL=http://evolution-api.rvt-dev.local:8080
```

**Sem mudança de código** — `requests.get(EVOLUTION_API_URL + ...)` continua igual. A "mágica" é toda fora do processo (glibc → iptables → envoy).

**Pegadinha conhecida**: secret com valor de outro env (ex.: `rvt-staging.local` no secret de dev) faz glibc cair em Route53 lookup → NXDOMAIN. Sempre validar que o valor do secret bate com o namespace do env.

---

## 5. Trace end-to-end — request `worker → evolution-api`

| # | Camada | O que acontece | Onde |
|---|---|---|---|
| 1 | App | Worker-agent lê `EVOLUTION_API_URL` do env | `task-definitions/worker-agent.json:95` |
| 2 | Secret | Valor esperado: `http://evolution-api.rvt-dev.local:8080` | AWS Secrets Manager |
| 3 | App | `requests.get(EVOLUTION_API_URL + "/...")` | código da app |
| 4 | glibc | `getaddrinfo("evolution-api.rvt-dev.local")` consulta `/etc/hosts` | `/etc/hosts` populado pelo ECS Agent |
| 5 | glibc | Retorna `127.255.X.X` (IP fake do envoy) | — |
| 6 | Kernel | App abre TCP em `127.255.X.X:8080` | — |
| 7 | iptables | Regra NAT REDIRECT → `127.0.0.1:15001` | Instalada pelo envoy |
| 8 | Envoy (worker) | Recebe outbound, identifica cluster `evolution-api` | imagem AWS |
| 9 | Envoy (worker) | Catálogo lista IPs vivos (ex.: `10.0.2.34`), seleciona um | Push do ECS Agent local |
| 10 | Envoy (worker) | Abre TCP pra `10.0.2.34:15006` (inbound do envoy destino) | — |
| 11 | Rede VPC | Pacote cruza subnets privadas | `revertai/<region>/<env>/vpc/` |
| 12 | SG destino | Ingress 8080/tcp from VPC CIDR | `service-evolution-api/terragrunt.hcl` |
| 13 | Envoy (evo) | Inbound, encaminha pra `localhost:8080` | — |
| 14 | App evolution | Node escutando em `0.0.0.0:8080` recebe HTTP | `evolution-api.json` |
| 15 | Resposta | Volta pelo caminho inverso | — |

### Onde quebra na prática

- **SG do destino restritivo demais** — se ingress não permitir do CIDR de origem, conexão é dropada.
- **`EVOLUTION_API_URL` com namespace de outro env** — glibc não acha no `/etc/hosts`, cai em DNS lookup → NXDOMAIN.
- **portName mismatch** entre `service_connect_configuration.service[].port_name` e `portMappings[].name` — não publica alias, falha silenciosa.
- **Task subiu antes do envoy escrever `/etc/hosts`** — primeira request falha. ECS usa `dependsOn` pra mitigar.
- **App com `requests.Session()` keep-alive agressivo** — conexão pinada num upstream do envoy; quando destino recicla, primeira request via pool quebra. Não é bug do SC, é HTTP/1.1 normal.

---

## 6. Debugging

### Confirmar que SC está rodando numa task

```bash
aws ecs describe-tasks --cluster <cluster> --tasks <task-arn> \
  --query 'tasks[0].containers[].{name:name,image:image}'
```

Esperado: 2 containers — o seu app + `ecs-service-connect-<rev>` (imagem AWS).

### Ver endpoints registrados no Cloud Map

```bash
aws servicediscovery list-namespaces --query "Namespaces[?Name=='rvt-dev.local']"

aws servicediscovery list-services --filters Name=NAMESPACE_ID,Values=<ns-id>

aws servicediscovery list-instances --service-id <service-id>
```

### Smoke test de dentro de uma task

```bash
aws ecs execute-command --cluster <cluster> --task <arn-task> \
  --container <container-name> --interactive --command "/bin/sh"
```

```sh
# Dentro do container:
getent hosts evolution-api.rvt-dev.local
# Esperado: IP da faixa 127.255.0.0/16

curl -sv http://evolution-api.rvt-dev.local:8080/ -m 5
# Esperado: HTTP 200 (ou 404 se path errado, mas conecta)

cat /etc/hosts | grep rvt
# Esperado: linha mapeando o alias pra 127.255.X.X
```

### Logs do envoy

Vão pro mesmo log group da task com stream prefix `ecs-service-connect`. Filtrar por `WARN`/`ERROR` pra ver falhas de upstream.

### Métricas

CloudWatch → Metrics → `AWS/ECS/ServiceConnect` (filtrar por `TargetDiscoveryName`). `RequestCount = 0` por muito tempo = nada chamando esse alias (ou alias quebrado).

### Validar serviceConnectConfiguration via API

```bash
aws ecs describe-services --cluster <cluster> --services <svc> \
  --query 'services[0].{enabled:serviceConnectConfiguration.enabled,services:serviceConnectConfiguration.services}'
```

---

## 7. Estendendo pra novos services

### Checklist pra adicionar SC server (publica alias)

1. **Task def** (`nix_webserver/task-definitions/<x>.json`):
   - Adicionar `"name": "<discovery-name>-<port>"` no portMapping.
   - Adicionar `"appProtocol": "http"` se for HTTP (melhora métricas).
   - Adicionar `healthCheck` no container (ver §4.4).

2. **Terragrunt** (`revertai/<region>/<env>/apps/<app>/service-<x>/terragrunt.hcl`):
   - Adicionar bloco `service_connect_configuration` modo server (ver §4.2).
   - **`port_name` precisa bater** com `portMappings[].name` da task-def.

3. **SG ingress**: garantir que tasks de origem conseguem alcançar a porta. Em dev, `ingress` permite do `vpc_cidr` inteiro — ajuste pra prod conforme política.

4. **Sizing da task**: aumentar `cpu`/`memory` da task-def em ~50 mCPU + 256 MiB pro envoy sidecar.

5. **`terragrunt apply`** no service.

6. **Validar**:
   ```bash
   aws servicediscovery list-services  # ver alias criado
   aws ecs describe-tasks ...           # ver sidecar injetado
   ```

### Checklist pra adicionar SC client

1. **Task def**: nenhuma mudança obrigatória.

2. **Terragrunt**: adicionar `service_connect_configuration = { enabled = true }` no service.

3. **App** consome via hostname `<alias>.rvt-<env>.local:<porta>` — geralmente via secret/env var.

4. **`terragrunt apply`** + force-redeploy da task pra envoy ser injetado.

---

## 8. Migração de Cloud Map clássico → SC (staging/prod)

Se um env já estiver em Cloud Map clássico (`service_registries` + `aws_service_discovery_service` manuais), migração possível mas requer ordem:

| Apply | Mudança | Risco |
|---|---|---|
| 1 | Adicionar `service_connect_configuration` no terragrunt **sem remover** `service_registries`. Tasks registram nos dois sistemas em paralelo. | Baixo — comportamento aditivo |
| — | Validar SC via CloudWatch metrics (`RequestCount` > 0) | — |
| 2 | Mudar valor do secret (`EVOLUTION_API_URL`, etc.) pro novo hostname SC. Force-redeploy clients. | Médio — depende de cache de DNS no cliente |
| 3 | Remover `service_registries` do terragrunt + remover `aws_service_discovery_service` manual. | Baixo após cutover |
| 4 | Opcional: destruir Private DNS namespace antigo e recriar HTTP namespace (custo $0). Requer janela curta sem discovery. | Médio — só fazer com todos clients confirmados em SC |

**Conflitos comuns**:

- Namespace já existe com mesmo nome → `terraform import` pra trazer pro state.
- `aws_service_discovery_service` manual com mesmo nome que o SC tentaria criar (`discovery_name`) → remover antes de aplicar SC.
- ECS service com `service_registries[]` E `service_connect_configuration` ativos → ECS aceita ambos, comportamento confuso. Remover `service_registries` no apply seguinte.

**Diagnóstico inicial** do env target:

```bash
aws servicediscovery list-namespaces \
  --query "Namespaces[].{Name:Name,Type:Type,Id:Id}"

# Pra cada namespace:
aws servicediscovery list-services --filters Name=NAMESPACE_ID,Values=<id>

# Pra cada ECS service do env:
aws ecs describe-services --cluster <c> --services <s> \
  --query 'services[0].{registries:serviceRegistries,sc:serviceConnectConfiguration}'
```

Output guia a estratégia:

| Estado descoberto | Significa |
|---|---|
| `Type: HTTP` + `serviceConnectConfiguration.enabled: true` | Já em SC. Replicar dev é seguro. |
| `Type: DNS_PRIVATE` + `serviceRegistries: [...]` + SC null | Cloud Map clássico. Migrar conforme tabela acima. |
| Sem namespaces | Greenfield. Criar do zero como em dev. |

---

## 9. Limitações conhecidas

### Do Service Connect

- **Mesmo cluster apenas**. SC não atravessa clusters ECS. Pra cross-cluster: ALB interno, App Mesh, ou Cloud Map clássico.
- **Sem mTLS automático** entre tasks. Tráfego intra-cluster é HTTP/TCP plano. Pra mTLS, usar App Mesh ou implementar no app.
- **Catálogo de instâncias por namespace**: limite AWS de 5000 instâncias por namespace HTTP. Em prod gigante, considerar split de namespaces.

### Do módulo `terraform-aws-modules/ecs//modules/service` v7.5.0

- **`client_alias` é objeto único**, não lista. AWS API permite múltiplos aliases por porta; o módulo limita a um. Pra múltiplos, usar `aws_ecs_service` resource direto.
- **`service_connect_configuration` é `type = any`** no nosso wrapper (`modules/ecs-service-app-managed/variables.tf`). Erros de tipo só aparecem no plan do módulo upstream, não na validação do nosso wrapper.

### Operacional

- **Sem health check no task-def → SC roteia pra task com app travado**. Adicionar `containerDefinitions[].healthCheck` em servers críticos (ver §4.4).
- **Cold start do envoy** adiciona ~5-10s no startup da task. Refletir no `startPeriod` do health check da app.

---

## 10. Referências cruzadas no repo

| Conceito | Arquivo | Linhas-chave |
|---|---|---|
| Namespace Cloud Map | `revertai/sa-east-1/dev/cloudmap/terragrunt.hcl` | 45-49, 81-85 |
| Cluster default namespace | `revertai/sa-east-1/dev/ecs-cluster/terragrunt.hcl` | 54-56 |
| Server config (Evolution) | `revertai/sa-east-1/dev/apps/nix_webserver/service-evolution-api/terragrunt.hcl` | 108-118 |
| Client config (web) | `revertai/sa-east-1/dev/apps/nix_webserver/service-web/terragrunt.hcl` | 135-137 |
| Wiring no módulo wrapper | `modules/ecs-service-app-managed/main.tf` | 113-115 |
| Type da variável | `modules/ecs-service-app-managed/variables.tf` | 113-125 |
| portMappings.name (server) | `nix_webserver/task-definitions/evolution-api.json` | 18-26 |
| healthCheck (server) | `nix_webserver/task-definitions/evolution-api.json` | 27-33 |
| EVOLUTION_API_URL secret ref | `nix_webserver/task-definitions/{web,worker-agent}.json` | (secrets block) |

---

## 11. Decisões de design (registro)

- **HTTP namespace, não Private DNS** — economiza $0.50/mês + queries Route53. SC funciona com ambos. Trocar pra Private DNS só se precisar resolver fora do ECS.
- **Namespace por env, naming `rvt-<env>.local`** — espelha staging (criado antes do dev). Mantém consistência entre envs.
- **Server único é Evolution API** — todos os outros services são consumers. Web é client mesmo expondo HTTP via ALB (ALB → web é caminho de entrada externo, não passa por SC).
- **Default namespace no cluster** (`service_connect_defaults`) — services não precisam declarar `namespace` individualmente. Menos repetição.
- **Sem mTLS** — dev. Pra prod, avaliar quando dados sensíveis trafegarem entre services (não é o caso atual; conteúdo já passa por TLS no ingress externo).
