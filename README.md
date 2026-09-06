# ToggleMaster — Infraestrutura (Terraform + Kubernetes/EKS)

Infraestrutura como código do ecossistema de microsserviços **ToggleMaster** na AWS (**EKS**), com alvo no **AWS Academy** (`LabRole`, sem criação de IAM).

- **`terraform/`** — provisiona toda a infraestrutura AWS (VPC, EKS, 3× RDS, Redis, DynamoDB, SQS, ECR) e cria o Namespace/Secret/ConfigMaps e os add-ons no cluster. Leia o [`terraform/README.md`](terraform/README.md).
- **`aws/`** — manifests Kubernetes (Kustomize) dos 5 microsserviços e as Applications do Argo CD. Leia o [`docs/CD-GITOPS.md`](docs/CD-GITOPS.md).

## Estrutura

```
toggle-master-infra/
├── terraform/
│   ├── bootstrap/            # bucket S3 do estado remoto (use_lockfile)
│   ├── infra/                # VPC, EKS (LabRole), RDS x3, ElastiCache, DynamoDB, SQS, ECR
│   ├── platform/             # namespace, Secret, ConfigMaps, metrics-server, ingress-nginx, Argo CD
│   └── modules/              # networking, eks, rds, elasticache, dynamodb, sqs, ecr
├── .github/workflows/
│   └── gitops-bump.yml       # o CI chama daqui para gravar a tag da imagem
└── aws/
    ├── platform/             # Jobs de init, Ingress e HPA — uma Application
    ├── apps/<serviço>/       # Deployment + Service + kustomization — uma Application cada
    ├── argocd/applications/  # as 6 Applications do Argo CD
    ├── keda/                 # exemplo KEDA (opcional; exige IRSA, fora do Academy)
    └── kustomization.yaml    # agrega tudo (fallback sem Argo CD)
```

## Arquitetura implantada

Cinco microsserviços, cada um como `Deployment` + `Service` (ClusterIP), expostos por um único **Nginx Ingress** (Network Load Balancer):

| Serviço | Porta | Persistência |
|---|---|---|
| auth-service (Go) | 8001 | RDS PostgreSQL `auth_db` |
| flag-service (Python) | 8002 | RDS PostgreSQL `flags_db` |
| targeting-service (Python) | 8003 | RDS PostgreSQL `targeting_db` |
| evaluation-service (Go) | 8004 | ElastiCache (Redis) + SQS |
| analytics-service (Python) | 8005 | SQS + DynamoDB `ToggleMasterAnalytics` |

Todos os Deployments têm `requests`/`limits`, probes de `readiness`/`liveness` em `/health`, `securityContext` restritivo (seccomp `RuntimeDefault`, sem escalada de privilégio, sem capabilities) e não montam token de service account. Os Jobs de init rodam `psql` como usuário `postgres` (não-root) com `ON_ERROR_STOP`, então um erro no SQL deixa o Job `Failed` em vez de `Complete`.

## Quem cria o quê

| Objeto | Dono | Motivo |
|---|---|---|
| Recursos AWS (VPC, EKS, RDS, Redis, DynamoDB, SQS, ECR) | `terraform/infra` | Requisito de IaC da Fase 3 |
| Namespace `toggle-master` (PSA `baseline`) | `terraform/platform` | Precisa existir antes do Secret |
| Secret `toggle-master-secrets` | `terraform/platform` | Valores vêm dos outputs reais do `infra` (remote state); `MASTER_KEY`/`SERVICE_API_KEY` geradas aleatoriamente |
| ConfigMap `toggle-master-config` | `terraform/platform` | Região e nome da tabela vêm do Terraform |
| ConfigMap `auth-db-init-sql` | `terraform/platform` | Contém o hash SHA-256 da `SERVICE_API_KEY` gerada |
| metrics-server, ingress-nginx | `terraform/platform` (Helm) | Eram instalados à mão |
| Deployments, Services, Jobs, Ingress, HPA | `aws/` (Kustomize) | Workloads — na etapa GitOps passam a ser sincronizados pelo ArgoCD |

## Deploy

Todos os comandos abaixo partem da raiz deste diretório (`toggle-master-infra/`).

### 1. Infraestrutura (Terraform)

Siga o [`terraform/README.md`](terraform/README.md): `bootstrap` → `infra` → `platform`. Ao final você terá o cluster, os bancos, a fila, os repositórios ECR e o namespace já com Secret e ConfigMaps.

### 2. Imagens

Publique as 5 imagens nos repositórios ECR criados:

```bash
terraform -chdir=terraform/infra output ecr_repository_urls
```

Os repositórios ECR seguem o padrão `togglemaster/<serviço>` (ex.: `togglemaster/auth-service`), o mesmo usado no código e no CI. Os Deployments referenciam só o nome do serviço (`auth-service:latest`); registry e tag ficam no bloco `images:` de `aws/apps/<serviço>/kustomization.yaml` — um por serviço, porque cada um é uma Application independente do Argo CD. É esse bloco que o CI reescreve com `kustomize edit set image auth-service=<registry>/togglemaster/auth-service:<tag>`. Se o ID da conta for diferente de `010533939486`, a primeira execução do CI corrige sozinha.

### 3. Workloads

```bash
aws eks update-kubeconfig --region us-east-1 --name toggle-master-dev-eks
kubectl apply -k aws
```

### 4. Verificar

```bash
kubectl -n toggle-master get jobs      # auth/flag/targeting-db-init = Complete
kubectl -n toggle-master get pods      # 5 serviços Running/Ready
kubectl -n toggle-master get ingress,hpa
kubectl -n ingress-nginx get svc ingress-nginx-controller   # DNS do NLB
```

## Acesso externo (Ingress)

| Path | Serviço |
|---|---|
| `/validate`, `/admin/keys`, `/auth/*` | auth-service |
| `/flags` | flag-service |
| `/rules` | targeting-service |
| `/evaluate` | evaluation-service |
| `/analytics/*` | analytics-service |

O NLB expõe 80 e 443; o 443 usa o certificado autoassinado do controller (o lab não tem domínio), por isso `-k`. Envie a `MASTER_KEY` só por HTTPS. No Windows PowerShell use `curl.exe` (o `curl` é alias de `Invoke-WebRequest`) ou rode o bloco no Git Bash.

```bash
LB=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
MASTER_KEY=$(terraform -chdir=terraform/platform output -raw master_key)

curl -k "https://$LB/auth/health"
curl -k -X POST "https://$LB/admin/keys" -H "Authorization: Bearer $MASTER_KEY" \
     -H "Content-Type: application/json" -d '{"name":"demo"}'
curl -k "https://$LB/evaluate?user_id=user-123&flag_name=nova-home"
```

## Escalabilidade

`hpa.yaml` define HPA por CPU (alvo 70%) para `evaluation-service` (2–8 réplicas) e `analytics-service` (1–6). Esses dois Deployments não declaram `replicas`, para que um `kubectl apply`/sync do ArgoCD não desfaça a escala escolhida pelo HPA. O `keda/analytics-scaledobject.example.yaml` mostra a alternativa com KEDA escalando pelo tamanho da fila SQS — exige IRSA, indisponível no Academy.

## Observações do ambiente AWS Academy

- **LabRole**: cluster, nós e permissões de AWS (ECR, SQS, DynamoDB) usam a `LabRole` existente, importada no Terraform via `data "aws_iam_role"`.
- **Credenciais nos pods**: obtidas pela role do nó via IMDSv2; o launch template do node group define hop limit 2 (obrigatório em AL2023 para os containers alcançarem o IMDS).
- **Segredos**: nenhum valor real é versionado. Senhas do RDS e chaves da aplicação são geradas pelo Terraform e vivem no estado remoto (S3 criptografado) e no Secret do cluster. Os três estados (bootstrap, infra, platform) ficam no S3.
- **Custo**: ~US$ 8/dia com tudo ligado. Destrua (`platform` → `infra`) depois da demo.

## Entrega Contínua (CD) & GitOps

O Argo CD é instalado pelo `terraform/platform` e monitora este repositório: cada
serviço é uma Application apontando para `aws/apps/<serviço>/`, com `automated`,
`prune` e `selfHeal`. O CI dos microsserviços chama
`.github/workflows/gitops-bump.yml` ao final do pipeline, que grava a tag da
imagem no `kustomization.yaml` correspondente — nenhum pipeline tem credencial de
cluster. Detalhes em [`docs/CD-GITOPS.md`](docs/CD-GITOPS.md).

## Próximas etapas do Tech Challenge (fora deste diretório)

Pipelines de CI DevSecOps (GitHub Actions por serviço), que passam a chamar o
workflow de GitOps deste repositório.
