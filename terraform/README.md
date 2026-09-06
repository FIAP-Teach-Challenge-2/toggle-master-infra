# ToggleMaster — Infraestrutura como Código (Terraform)

Provisiona **toda** a infraestrutura AWS do ToggleMaster (Tech Challenge Fase 3) e injeta os endpoints/credenciais no cluster, substituindo a criação manual da Fase 2. Alvo: **AWS Academy** (usa a `LabRole` existente; nenhuma role ou policy de IAM é criada).

> "Se não está no código, não existe."

## O que é provisionado

| # | Recurso | Módulo | Detalhes |
|---|---|---|---|
| 1 | VPC, 2 subnets públicas + 2 privadas, IGW, NAT Gateway, route tables | `modules/networking` | Subnets com tags `kubernetes.io/*`; SG default da VPC sem regras |
| 2 | Cluster EKS + managed node group | `modules/eks` | `LabRole` no control plane **e** nos nós; launch template (IMDSv2 hop limit 2, disco gp3 criptografado); add-ons vpc-cni, kube-proxy, coredns; logs api/audit/authenticator no CloudWatch |
| 3 | 3× RDS PostgreSQL 16 (`auth_db`, `flags_db`, `targeting_db`) | `modules/rds` | Privados, criptografados, senha gerada, SG aceita só o SG do cluster |
| 3 | 1× ElastiCache Redis 7 | `modules/elasticache` | Privado, SG aceita só o SG do cluster |
| 3 | 1× DynamoDB `ToggleMasterAnalytics` | `modules/dynamodb` | PK `event_id`, sob demanda |
| 4 | 1× fila SQS `toggle-master-evaluations` (+ DLQ) | `modules/sqs` | Long polling 20 s, SSE |
| 5 | 5× repositórios ECR `togglemaster/<serviço>` | `modules/ecr` | `scan_on_push`, lifecycle de 10 imagens |
| — | Namespace, Secret, ConfigMaps, metrics-server, ingress-nginx (NLB) | `platform` | Substitui o `kubectl create secret` manual |
| — | Bucket S3 do estado remoto | `bootstrap` | Versionado, criptografado, `use_lockfile` |

## Estrutura

```
terraform/
├── bootstrap/     # Stage 0 — bucket S3 do estado (1x por conta; estado migrado para o próprio bucket)
├── infra/         # Stage 1 — recursos AWS (backend S3)
├── platform/      # Stage 2 — objetos no cluster + Helm (backend S3; lê o remote state do infra)
└── modules/
    ├── networking/
    ├── eks/
    ├── rds/
    ├── elasticache/
    ├── dynamodb/
    ├── sqs/
    └── ecr/
```

Por que três stacks? O `bootstrap` precisa existir antes de qualquer backend remoto. O `platform` usa os providers `kubernetes`/`helm`, que só podem ser configurados com um cluster **já existente** — separá-lo do `infra` evita o anti-padrão de configurar um provider com atributos de um recurso criado no mesmo `apply`. O `platform` lê os outputs do `infra` com `terraform_remote_state` (mesmo bucket S3) e monta o Secret/ConfigMaps a partir deles.

```
bootstrap ──(bucket)──▶ infra ──(remote state: cluster, URLs)──▶ platform ──▶ kubectl apply -k ../../aws
```

Os três estados (`bootstrap/`, `infra/`, `platform/`) ficam no bucket S3 — nenhum `terraform.tfstate` local. `region`, `encrypt` e `use_lockfile` estão nos `backend.tf` versionados; só o nome do bucket (específico da conta) fica no `backend.hcl`, fora do git.

## Pré-requisitos

- Terraform **>= 1.10** (o lock nativo `use_lockfile` do backend S3 exige 1.10+). Todo o grupo deve usar a **mesma versão minor** (ex.: 1.12.x): o Terraform não lê um estado gravado por uma versão mais nova, então se alguém aplicar com 1.16 os demais precisam atualizar.
- AWS CLI v2, `kubectl` e Docker (para publicar as imagens no ECR).
- Credenciais do AWS Academy exportadas no terminal (**AWS Details → AWS CLI** no Learner Lab: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`). Elas expiram a cada sessão do lab.
- Região `us-east-1` (padrão do Academy).

> **Windows PowerShell 5.1**: não use `>` para gravar arquivos que o Terraform lê (gera UTF-16). Use `Out-File -Encoding ascii` como mostrado abaixo, ou rode tudo no Git Bash. O operador `&&` também não existe no PowerShell 5.1: rode um comando por linha.

## Passo a passo

Todos os caminhos abaixo são relativos a `toggle-master-infra/terraform/`.

### 0. Bootstrap do estado remoto (uma vez por conta)

```bash
cd bootstrap
terraform init
terraform apply
```

Gere o `backend.hcl` dos três stacks (contém só `bucket = "toggle-master-tfstate-<ACCOUNT_ID>"`):

```bash
# bash / Git Bash / PowerShell 7+
terraform output -raw backend_hcl > backend.hcl
terraform output -raw backend_hcl > ../infra/backend.hcl
terraform output -raw backend_hcl > ../platform/backend.hcl
```

```powershell
# Windows PowerShell 5.1
terraform output -raw backend_hcl | Out-File -Encoding ascii backend.hcl
terraform output -raw backend_hcl | Out-File -Encoding ascii ..\infra\backend.hcl
terraform output -raw backend_hcl | Out-File -Encoding ascii ..\platform\backend.hcl
```

Migre o estado do próprio bootstrap para o bucket recém-criado (assim nenhum stack fica com estado local) e versione o `backend.tf`:

```bash
mv backend.tf.migrate backend.tf          # PowerShell: Rename-Item backend.tf.migrate backend.tf
terraform init -migrate-state -backend-config=backend.hcl
```

**Outros membros do grupo / nova máquina (mesma conta do lab):** todo o grupo deve usar as credenciais da **mesma** conta do Learner Lab (a que criou o bucket e a infra) — cada Learner Lab é uma conta separada. Nessa conta **não rode o `apply` do bootstrap de novo**: em `us-east-1` o S3 aceita recriar um bucket que já é seu, então o apply passa em silêncio e cria um segundo estado (local) para o mesmo bucket. Crie os três `backend.hcl` a partir dos `backend.hcl.example`, trocando `<ACCOUNT_ID>` por `aws sts get-caller-identity --query Account --output text`, e rode apenas `terraform init -backend-config=backend.hcl` em cada stack (no `bootstrap`, com o `backend.tf` já versionado, isso lê o estado migrado).

**Conta nova do zero (outro Learner Lab):** é um ambiente totalmente separado; o bucket ainda não existe lá, e o `backend.tf` versionado do bootstrap aponta para o S3. Volte ao estado local só para o primeiro apply e refaça a migração:

```bash
cd bootstrap
mv backend.tf backend.tf.migrate      # PowerShell: Rename-Item backend.tf backend.tf.migrate
rm -rf .terraform                     # PowerShell: Remove-Item -Recurse -Force .terraform
terraform init
terraform apply
# gere os três backend.hcl como acima, depois:
mv backend.tf.migrate backend.tf
terraform init -migrate-state -backend-config=backend.hcl
```

Depois siga `infra → platform` normalmente nessa conta.

### 0.5. Recursos manuais da Fase 2 (se ainda existirem)

A tabela DynamoDB `ToggleMasterAnalytics`, a fila `toggle-master-evaluations` e os 5 repositórios ECR têm nome fixo na conta. Se os criados à mão na Fase 2 ainda existirem, o `apply` falha com `ResourceInUseException` / `QueueAlreadyExists` / `RepositoryAlreadyExistsException`. Duas saídas:

- **Apagar** os recursos manuais no console (e publicar as imagens de novo depois), ou
- **Adotar** com `import`: copie `infra/import.tf.example` para `infra/import.tf`, ajuste o ID da conta na URL da fila e siga para o passo 1 — o `plan` mostra `N to import`, o `apply` adota os recursos e alinha os atributos (SSE, DLQ, scan on push). Apague o `import.tf` depois.

### 1. Infraestrutura AWS

```bash
cd ../infra
cp terraform.tfvars.example terraform.tfvars   # opcional: ajuste tamanhos/versões
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Leva ~15–20 min (EKS ~10 min, RDS ~5 min, em paralelo). Ao final:

```bash
terraform output                       # endpoints, nomes, URLs do ECR
terraform output -json database_urls   # sensível
terraform output -raw kubeconfig_command
```

### 2. Plataforma (objetos no cluster)

```bash
cd ../platform
terraform init -backend-config=backend.hcl
terraform apply
```

Cria o namespace `toggle-master` (com Pod Security Admission `baseline`), o Secret `toggle-master-secrets`, os ConfigMaps `toggle-master-config` e `auth-db-init-sql`, e instala **metrics-server** e **ingress-nginx** (Network Load Balancer) via Helm. As chaves `MASTER_KEY` e `SERVICE_API_KEY` são geradas aleatoriamente (o hash SHA-256 da `SERVICE_API_KEY` é semeado no `auth_db` pelo Job `auth-db-init`):

```bash
terraform output -raw master_key
terraform output -raw service_api_key
```

**Rotação de chaves:** se `service_api_key` ou `master_key` mudarem depois do primeiro deploy (variável alterada ou `terraform apply -replace=random_password.service_api_key`), o Secret e o ConfigMap são atualizados, mas os pods leem o Secret como variáveis de ambiente e o Job `auth-db-init` já concluído não roda de novo. Re-semeie e reinicie:

```bash
kubectl -n toggle-master delete job auth-db-init
kubectl apply -k ../../aws
kubectl -n toggle-master rollout restart deploy/auth-service deploy/evaluation-service
```

O SQL do Job desativa os hashes antigos e ativa o novo, então a chave anterior deixa de funcionar.

### 3. Deploy dos microsserviços

Publique as 5 imagens nos repositórios ECR criados. Os nós são **x86_64** (`AL2023_x86_64_STANDARD`): em Mac Apple Silicon use `--platform linux/amd64`, senão os pods caem em `CrashLoopBackOff` com `exec format error`. Até a etapa de CI, o push é manual (ainda em `platform/`):

```bash
ACCOUNT=$(terraform -chdir=../infra output -raw account_id)
REGISTRY=$ACCOUNT.dkr.ecr.us-east-1.amazonaws.com
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REGISTRY
for s in auth-service flag-service targeting-service evaluation-service analytics-service; do
  docker build --platform linux/amd64 -t $REGISTRY/togglemaster/$s:latest ../../../$s
  docker push $REGISTRY/togglemaster/$s:latest
done
```

```powershell
# Windows PowerShell 5.1
$ACCOUNT  = terraform -chdir=../infra output -raw account_id
$REGISTRY = "$ACCOUNT.dkr.ecr.us-east-1.amazonaws.com"
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REGISTRY
foreach ($s in "auth-service","flag-service","targeting-service","evaluation-service","analytics-service") {
  docker build --platform linux/amd64 -t "$REGISTRY/togglemaster/${s}:latest" "../../../$s"
  docker push "$REGISTRY/togglemaster/${s}:latest"
}
```

Os repositórios são `togglemaster/<serviço>` (`terraform -chdir=../infra output ecr_repository_urls`). O registry usado pelos Deployments está centralizado no bloco `images:` de `../../aws/kustomization.yaml`; se o ID da conta for diferente de `010533939486`, ajuste ali (ou `kustomize edit set image auth-service=<registry>/togglemaster/auth-service:<tag>`). Então:

```bash
aws eks update-kubeconfig --region us-east-1 --name toggle-master-dev-eks
kubectl apply -k ../../aws
kubectl -n toggle-master get jobs,pods,svc,ingress,hpa
kubectl -n ingress-nginx get svc ingress-nginx-controller   # DNS do NLB
```

Confirme que os pods conseguem usar as credenciais do nó (IMDS): `kubectl -n toggle-master logs deploy/analytics-service | grep -i credential` deve vir vazio e `kubectl -n toggle-master logs deploy/evaluation-service | grep "enviado para SQS"` deve aparecer após uma chamada a `/evaluate`. No PowerShell 5.1 troque `| grep -i credential` por `| Select-String -Pattern credential` e `| grep "enviado para SQS"` por `| Select-String "enviado para SQS"`.

### 4. Destruir (ordem inversa)

```bash
cd ../platform
terraform destroy      # remove o NLB do ingress antes da VPC
cd ../infra
terraform destroy
```

Após o destroy do `infra`, o EKS ainda entrega os últimos logs do control plane por alguns minutos e costuma **recriar** o log group fora do estado. Antes de um novo `apply`, apague-o (senão o apply falha com `ResourceAlreadyExistsException`):

```bash
aws logs delete-log-group --log-group-name /aws/eks/toggle-master-dev-eks/cluster
```

O bucket do `bootstrap` é mantido de propósito (`prevent_destroy`); apague-o manualmente se quiser encerrar a conta.

## Notas sobre o AWS Academy

- **IAM**: `infra/main.tf` importa a role com `data "aws_iam_role" "lab" { name = var.lab_role_name }` e passa o ARN para `cluster_role_arn` e `node_role_arn` do módulo EKS. Nenhum recurso `aws_iam_*` existe no código.
- **Cluster admin**: `bootstrap_cluster_creator_admin_permissions = true` concede cluster-admin ao principal que executa o `apply` do `infra`. Rode o `infra` **sempre com as credenciais do Learner Lab** (AWS Details → AWS CLI, role `voclabs`) e use as mesmas credenciais no `platform` e no `kubectl`. **Não** rode o `apply` do `infra` de um Cloud9/EC2 com `LabInstanceProfile`: aí o criador do cluster seria a própria `LabRole`, que receberia um access entry STANDARD, e o node group (também `LabRole`) precisaria de um segundo access entry EC2_LINUX para o mesmo principal — o EKS não permite um principal em mais de um access entry e a criação do node group falha.
- **Credenciais dos pods**: os serviços usam a role do nó (`LabRole`) via **IMDSv2**; não há IRSA. Em AL2023 um node group sem launch template recebe hop limit 1 e os containers **não** enxergam o IMDS, por isso o módulo cria um launch template com `http_put_response_hop_limit = 2`. Consequência aceita no lab: qualquer pod do cluster pode obter as credenciais da LabRole.
- **Sessões expiram**: se um `apply` longo falhar com `ExpiredToken`, exporte credenciais novas e rode `terraform apply` de novo — o estado remoto garante a continuidade.
- **End Lab / fim das 4 h**: o Learner Lab **para as instâncias EC2** dos nós. Ao reiniciar o lab, o Auto Scaling do node group substitui as instâncias paradas por novas (todos os pods reiniciam; DNS do NLB e endpoints de RDS/Redis não mudam). Control plane do EKS, RDS, Redis, NAT Gateway e NLB **continuam cobrando** com o lab encerrado — só o `terraform destroy` para a cobrança.
- **Conta nova (outro membro)**: as service-linked roles (EKS, node group, Auto Scaling, ELB do ingress, RDS, ElastiCache) são criadas no primeiro `apply`; o Learner Lab avisa que essa criação pode falhar na primeira tentativa — basta rodar `terraform apply` de novo.
- **Conta pessoal (Opção B)**: crie previamente uma role com trust para `eks.amazonaws.com` e `ec2.amazonaws.com` e as policies `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy` e `AmazonEC2ContainerRegistryReadOnly`, e informe o nome em `lab_role_name`.

## Variáveis mais relevantes (`infra`)

| Variável | Default | Observação |
|---|---|---|
| `lab_role_name` | `LabRole` | Role existente para cluster e nós |
| `eks_cluster_version` | `1.35` | Suporte padrão até 27/03/2027. 1.34 sai em 02/12/2026 e passa a custar US$ 0,60/h (`aws eks describe-cluster-versions`) |
| `eks_cluster_support_type` | `STANDARD` | A AWS faz o upgrade automático do control plane ao fim do suporte padrão (27/03/2027 para 1.35) em vez de cobrar suporte estendido (o padrão da AWS é `EXTENDED`). Antes dessa data suba `eks_cluster_version` (ex.: 1.36) e aplique, senão o `plan` passa a propor um downgrade que o EKS rejeita e os nós ficam uma versão atrás |
| `eks_enabled_cluster_log_types` | `api, audit, authenticator` | Logs do control plane no CloudWatch (retenção 7 dias) |
| `ecr_image_tag_mutability` | `MUTABLE` | Mude para `IMMUTABLE` quando o CI publicar só tags de commit |
| `eks_node_instance_types` / `eks_node_desired_size` | `["t3.medium"]` / `2` | |
| `enable_nat_gateway` | `true` | Desligue só com `eks_nodes_in_public_subnets = true` |
| `eks_nodes_in_public_subnets` | `false` | Modo econômico |
| `rds_instance_class` | `db.t3.micro` | Menor classe suportada pelo PG 16 (~US$ 13/mês cada; o Academy não tem free tier) |
| `rds_storage_type` | `gp3` | A planilha de restrições do Learner Lab lista só `gp2` para RDS; troque se o apply for recusado |
| `redis_node_type` | `cache.t3.micro` | |
| `dynamodb_table_name` | `ToggleMasterAnalytics` | Nome exigido pelo analytics-service |
| `sqs_queue_name` | `toggle-master-evaluations` | |

## Segurança

- Nenhum segredo no repositório: senhas do RDS e chaves da aplicação vêm de `random_password`; `*.tfvars` e `backend.hcl` estão no `.gitignore`; outputs sensíveis são marcados como `sensitive`. Os valores vivem no estado remoto (S3 criptografado, sem acesso público) e no Secret do cluster.
- Estado remoto criptografado (SSE-S3), versionado, bloqueado a acesso público e com lock nativo.
- RDS e Redis em subnets privadas, sem IP público; security groups aceitam conexão apenas do security group do cluster e não têm regra de egress; SG default da VPC sem regras.
- RDS com criptografia em repouso e `sslmode=require`; discos dos nós criptografados; SQS com SSE; ECR com scan a cada push; logs de auditoria do EKS no CloudWatch.
- Todos os pods (5 Deployments e 3 Jobs) rodam com `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` e sem token de service account; os Jobs `psql` rodam como o usuário `postgres` (UID 70). O namespace impõe Pod Security Admission `baseline` e apenas **avisa** sobre `restricted` (avisos esperados no `kubectl apply`): as imagens dos serviços usam o usuário nomeado `app` sem UID fixo, e o kubelet não consegue verificar `runAsNonRoot` sem um `runAsUser` numérico. Para chegar a `restricted`, fixe o UID nos Dockerfiles (`adduser -u 10001 ...` + `USER 10001`) e adicione `runAsNonRoot`/`runAsUser` aos manifests.
- **Trade-offs aceitos no laboratório** (documentados de propósito):
  - O `platform` lê o **estado completo** do `infra` via `terraform_remote_state` (a HashiCorp desaconselha quando há dados sensíveis). Aceito porque bucket, conta e principal são os mesmos. Consequências: as `DATABASE_URL`s existem em dois estados (`infra/` e `platform/`, que também guarda o conteúdo do Secret) e quem tem `s3:GetObject` no bucket lê todas as senhas. Os outputs chegam **sem** a marca `sensitive` (hashicorp/terraform#29544), por isso o `platform` os reembrulha com `sensitive()`.
  - Itens que scanners (checkov/tfsec/trivy) apontam e são decisões conscientes: ECR com tags mutáveis e `:latest` enquanto o push é manual (mude `ecr_image_tag_mutability = "IMMUTABLE"` quando o CI publicar tags de commit); cluster sem `encryption_config` (desde o Kubernetes 1.28 o EKS aplica envelope encryption a todos os dados da API com chave da AWS; uma CMK custaria US$ 1/mês); logs do control plane limitados a `api/audit/authenticator` por custo; hop limit 2 do IMDS é obrigatório sem IRSA (veja Notas sobre o AWS Academy); o Redis (`aws_elasticache_cluster`) não tem criptografia em repouso nem em trânsito e guarda apenas cache de avaliações.
  - O endpoint público da API do EKS é aberto (`eks_public_access_cidrs = 0.0.0.0/0`); restrinja ao seu IP em produção.
  - O Redis (`aws_elasticache_cluster`) não usa TLS nem AUTH: só é alcançável de dentro da VPC pelo SG do cluster. Para TLS/AUTH use `aws_elasticache_replication_group` (`rediss://`).
  - A entrada pública (NLB → ingress) não tem certificado válido porque o lab não tem domínio. Use `https://$LB` com `curl -k` (certificado autoassinado do controller) e não exponha a `MASTER_KEY` em `http://` fora do lab; com um domínio, termine TLS no NLB com ACM.
  - O **ingress-nginx foi aposentado** pelo projeto Kubernetes em março/2026 (repositório arquivado, sem correções de segurança). Está fixado no último chart (`4.15.1`, suporta Kubernetes até 1.35) apenas para o laboratório. Para produção migre para um controller mantido (Gateway API com Envoy Gateway, Traefik ou AWS Load Balancer Controller), ajustando as anotações `nginx.ingress.kubernetes.io/*` de `aws/ingress.yaml`.

## Estimativa de custo (us-east-1, on-demand)

| Recurso | US$/mês |
|---|---|
| EKS control plane (suporte padrão, US$ 0,10/h) | ~73 |
| 2× t3.medium | ~61 |
| 3× db.t3.micro + 60 GB gp3 | ~44 |
| cache.t3.micro | ~12 |
| NAT Gateway | ~33 + tráfego |
| NLB (ingress) | ~16 |
| DynamoDB / SQS / ECR / CloudWatch Logs | ~2 |
| **Total** | **~240 (≈ US$ 8/dia)** |

Em suporte estendido o control plane custa US$ 0,60/h (~US$ 438/mês); mantenha `eks_cluster_version` em suporte padrão. No Academy os créditos são limitados: suba o ambiente para gravar a demo e rode `terraform destroy` em seguida. Use a [AWS Pricing Calculator](https://calculator.aws/) para o print exigido no relatório.

## Solução de problemas

| Sintoma | Causa provável | Ação |
|---|---|---|
| `Invalid character encoding` no `terraform init` | `backend.hcl` gravado em UTF-16 pelo `>` do Windows PowerShell 5.1 | Regrave com `Out-File -Encoding ascii` ou use Git Bash |
| `terraform apply` do bootstrap "criou" um bucket que já existia | Apply repetido na mesma conta (`us-east-1` não devolve `BucketAlreadyOwnedByYou`) | Apague o `terraform.tfstate` local do bootstrap e use `terraform init -backend-config=backend.hcl` para ler o estado migrado |
| `Failed to get existing workspaces: S3 bucket ... does not exist` no `terraform init` | `backend.hcl` aponta para o ID de outra conta (credenciais de um membro diferente), ou você está subindo o bootstrap numa conta nova com o `backend.tf` já versionado | Exporte as credenciais da conta que rodou o bootstrap; ou, na conta nova, renomeie `backend.tf` → `backend.tf.migrate`, faça o apply local e migre de novo |
| `ResourceAlreadyExistsException: The specified log group already exists` no `apply` do `infra` | O EKS recriou `/aws/eks/toggle-master-dev-eks/cluster` depois do `destroy` (ou ele sobrou de um cluster manual homônimo) | `aws logs delete-log-group --log-group-name /aws/eks/toggle-master-dev-eks/cluster` e rode o apply de novo, ou adote com o bloco `import` de `import.tf.example` |
| `aws_eks_node_group` falha e o cluster foi criado com credenciais da `LabRole` (Cloud9/EC2) | Criador do cluster e role dos nós são o mesmo principal (access entry duplicado) | Destrua e recrie o `infra` com as credenciais `voclabs` do Learner Lab |
| Job `auth-db-init` = Failed | Erro no SQL (o `psql` roda com `ON_ERROR_STOP`) | `kubectl -n toggle-master logs job/auth-db-init` |
| `ResourceInUseException` / `QueueAlreadyExists` / `RepositoryAlreadyExistsException` | Recurso manual da Fase 2 ainda existe | Importe com `infra/import.tf.example` ou apague-o |
| `data.aws_iam_role.lab: NoSuchEntity` | Role não existe na conta | Confira `lab_role_name` |
| `AccessDenied` ao criar EKS | Credenciais do lab expiradas ou role sem trust `eks.amazonaws.com` | Reexporte credenciais / verifique a role |
| `Unauthorized` no `platform` ou `kubectl` | Credenciais diferentes das usadas no `infra` | Use o mesmo principal ou adicione um access entry |
| Add-on `coredns` demora / DEGRADED | Nós ainda não prontos | Aguarde; o módulo cria o coredns só após o node group |
| Pods `ImagePullBackOff` | Imagens não publicadas, ID da conta diferente no `images:` do kustomization ou nós sem saída à internet | Publique as imagens; ajuste o registry; confira `enable_nat_gateway` |
| Pods `CrashLoopBackOff` com `exec format error` | Imagem construída para arm64 (Mac Apple Silicon) | Rebuild com `--platform linux/amd64` |
| `NoCredentialProviders` / `NoCredentialsError` nos logs do evaluation/analytics | Pods sem acesso ao IMDS (hop limit 1) | Confirme `node_imds_hop_limit = 2` no launch template do node group |
| `terraform destroy` do `infra` trava na VPC | NLB do ingress ainda existe | Destrua o `platform` antes |
