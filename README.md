# ToggleMaster — Manifestos Kubernetes (AWS EKS)

Manifestos para implantar o ecossistema de microsserviços **ToggleMaster** em um cluster **Kubernetes na AWS (EKS)**. O ambiente-alvo é o **AWS Academy**, então o deploy usa a **`LabRole`** e o autoscaling é feito por **HPA (CPU)** — o KEDA fica como exemplo opcional (depende de IRSA, indisponível no Academy).

## Estrutura

```
k8s/
└── aws/
    ├── namespace.yaml            # namespace "toggle-master"
    ├── configmap.yaml            # URLs internas, região, nome da tabela DynamoDB
    ├── secrets.template.yaml     # MODELO do Secret (valores placeholder — não aplicar)
    ├── db-init-jobs.yaml         # Jobs psql: criam tabelas e semeiam a API key nos RDS
    ├── apps/
    │   ├── auth-service.yaml         # Deployment + Service (porta 8001)
    │   ├── flag-service.yaml         # Deployment + Service (porta 8002)
    │   ├── targeting-service.yaml    # Deployment + Service (porta 8003)
    │   ├── evaluation-service.yaml   # Deployment + Service (porta 8004)
    │   └── analytics-service.yaml    # Deployment + Service (porta 8005)
    ├── ingress.yaml              # Nginx Ingress (roteamento por path)
    ├── hpa.yaml                  # HorizontalPodAutoscaler (evaluation + analytics)
    ├── keda/
    │   └── analytics-scaledobject.example.yaml   # exemplo KEDA (opcional, conta pessoal)
    └── kustomization.yaml        # agrega todos os recursos
```

## Arquitetura implantada

Cinco microsserviços, cada um como `Deployment` + `Service` (ClusterIP), expostos externamente por um único **Nginx Ingress** (Load Balancer na AWS):

| Serviço | Porta | Persistência |
|---|---|---|
| auth-service (Go) | 8001 | RDS PostgreSQL |
| flag-service (Python) | 8002 | RDS PostgreSQL |
| targeting-service (Python) | 8003 | RDS PostgreSQL |
| evaluation-service (Go) | 8004 | ElastiCache (Redis) + SQS |
| analytics-service (Python) | 8005 | SQS + DynamoDB |

Todos os Deployments usam `requests`/`limits` de CPU e memória e `readiness`/`liveness probes` no endpoint `/health`.

## Pré-requisitos

Antes de aplicar os manifestos, é preciso ter provisionado:

- Cluster **EKS** ativo + managed node group com a **LabRole** (permite pull no ECR e acesso a SQS/DynamoDB).
- **Metrics Server** instalado (necessário para o HPA).
- **Nginx Ingress Controller** instalado (provisiona o Load Balancer).
- **5 imagens** publicadas no ECR (`010533939486.dkr.ecr.us-east-1.amazonaws.com/<serviço>:latest`).
- **3 RDS PostgreSQL** (`auth_db`, `flags_db`, `targeting_db`), **ElastiCache Redis**, tabela **DynamoDB `ToggleMasterAnalytics`** (PK `event_id`) e uma fila **SQS**.
- **Security groups** liberando 5432 (RDS) e 6379 (Redis) para o SG dos nós.

## Deploy

### 1. Criar o Secret real

O `secrets.template.yaml` contém apenas valores placeholder e **não deve ser aplicado**. Crie o Secret com os endpoints reais:

```bash
kubectl create namespace toggle-master

kubectl -n toggle-master create secret generic toggle-master-secrets \
  --from-literal=AUTH_DATABASE_URL="postgres://toggle:SENHA@ENDPOINT_AUTH:5432/auth_db?sslmode=require" \
  --from-literal=FLAG_DATABASE_URL="postgres://toggle:SENHA@ENDPOINT_FLAG:5432/flags_db?sslmode=require" \
  --from-literal=TARGETING_DATABASE_URL="postgres://toggle:SENHA@ENDPOINT_TARG:5432/targeting_db?sslmode=require" \
  --from-literal=REDIS_URL="redis://ENDPOINT_REDIS:6379" \
  --from-literal=AWS_SQS_URL="https://sqs.us-east-1.amazonaws.com/010533939486/toggle-master-evaluations" \
  --from-literal=MASTER_KEY="admin-secreto-123" \
  --from-literal=SERVICE_API_KEY="tm_key_local_dev"
```

> `SERVICE_API_KEY` deve ser `tm_key_local_dev` — o `db-init-jobs.yaml` semeia o hash SHA-256 exato dessa chave no banco do auth. Use `rediss://` no `REDIS_URL` se o Redis for Serverless (TLS obrigatório).

### 2. Aplicar os manifestos

Certifique-se de que o `kustomization.yaml` **não** inclui `secrets.template.yaml` (você criou o Secret real acima). Então:

```bash
kubectl apply -k k8s/aws
```

Isso cria o namespace, o ConfigMap, os Jobs de init, os 5 Deployments + Services, o Ingress e os HPAs.

### 3. Verificar

```bash
kubectl -n toggle-master get jobs      # auth/flag/targeting-db-init = Complete
kubectl -n toggle-master get pods      # 5 serviços Running/Ready
kubectl -n toggle-master get svc
kubectl -n toggle-master get ingress
kubectl -n toggle-master get hpa
```

## Acesso externo (Ingress)

O `ingress.yaml` roteia por path a partir do DNS do Load Balancer:

| Path | Serviço |
|---|---|
| `/validate`, `/admin/keys`, `/auth/*` | auth-service |
| `/flags` | flag-service |
| `/rules` | targeting-service |
| `/evaluate` | evaluation-service |
| `/analytics/*` | analytics-service |

Exemplo:

```bash
LB=<DNS-DO-LOAD-BALANCER>
curl "http://$LB/auth/health"
curl "http://$LB/evaluate?user_id=user-123&flag_name=nova-home"
```

## Escalabilidade

O `hpa.yaml` define HPA por **CPU** (alvo 70%) para:

- `evaluation-service` — min 2, max 8 réplicas.
- `analytics-service` — min 1, max 6 réplicas (quando a fila enche, a CPU sobe ao processar e o HPA escala).

O arquivo `keda/analytics-scaledobject.example.yaml` mostra a alternativa com **KEDA** escalando o analytics diretamente pelo tamanho da fila SQS (`queueLength`) — recomendado em conta pessoal (fora do Academy), pois exige IRSA.

## Observações do ambiente AWS Academy

- **LabRole:** cluster, nós e permissões de AWS (ECR, SQS, DynamoDB) usam a `LabRole` existente; não é possível criar novas IAM roles.
- **Credenciais nos pods:** os pods obtêm as permissões de AWS pela role do nó (LabRole) via IMDS.
- **Secrets:** os valores reais **não** são versionados. Apenas o `secrets.template.yaml` (com placeholders) fica no repositório.
