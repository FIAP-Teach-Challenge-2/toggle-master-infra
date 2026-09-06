# ---------------------------------------------------------------------------
# Geral
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nome do projeto (prefixo de nomes e tags)."
  type        = string
  default     = "toggle-master"
}

variable "environment" {
  description = "Ambiente (prefixo de nomes e tags)."
  type        = string
  default     = "dev"
}

variable "lab_role_name" {
  description = "Nome da IAM role existente usada pelo cluster EKS e pelos nós. No AWS Academy é a LabRole; nenhuma role é criada."
  type        = string
  default     = "LabRole"
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Quantidade de zonas de disponibilidade (mínimo 2 para o EKS)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count deve ser 2 ou 3."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas (usa os az_count primeiros)."
  type        = list(string)
  default     = ["10.0.100.0/24", "10.0.101.0/24", "10.0.102.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (usa os az_count primeiros). /20 para dar folga aos IPs consumidos pelo vpc-cni."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway (necessário para nós em subnets privadas alcançarem ECR/SQS/DynamoDB). Desligue apenas com eks_nodes_in_public_subnets = true."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Um único NAT Gateway para todas as AZs (mais barato)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------

variable "eks_cluster_version" {
  description = "Versão do Kubernetes. Prefira uma versão em suporte padrão (aws eks describe-cluster-versions): fora dele o control plane custa US$ 0,60/h em vez de US$ 0,10/h. 1.35 tem suporte padrão até 2027-03-27."
  type        = string
  default     = "1.35"
}

variable "eks_cluster_support_type" {
  description = "STANDARD (auto-upgrade ao fim do suporte padrão; nunca paga suporte estendido) ou EXTENDED (padrão da AWS)."
  type        = string
  default     = "STANDARD"
}

variable "eks_enabled_cluster_log_types" {
  description = "Logs do control plane enviados ao CloudWatch (api, audit, authenticator, controllerManager, scheduler). Retenção de 7 dias; custo apenas de ingestão/armazenamento."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "eks_authentication_mode" {
  description = "Modo de autenticação do cluster (API_AND_CONFIG_MAP é compatível com aws-auth e access entries)."
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "eks_public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint público da API do cluster."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_nodes_in_public_subnets" {
  description = "Lança os nós em subnets públicas (modo econômico, dispensa NAT Gateway)."
  type        = bool
  default     = false
}

variable "eks_node_instance_types" {
  description = "Tipos de instância dos nós."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_capacity_type" {
  description = "ON_DEMAND ou SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "eks_node_disk_size" {
  description = "Disco raiz dos nós em GiB (mínimo 20, tamanho do snapshot da AMI AL2023)."
  type        = number
  default     = 20

  validation {
    condition     = var.eks_node_disk_size >= 20
    error_message = "eks_node_disk_size deve ser >= 20 GiB."
  }
}

variable "eks_node_desired_size" {
  description = "Nós desejados."
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Nós mínimos."
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Nós máximos."
  type        = number
  default     = 3
}

# ---------------------------------------------------------------------------
# Bancos de dados
# ---------------------------------------------------------------------------

variable "rds_databases" {
  description = "Instâncias RDS PostgreSQL a criar (chave = sufixo do identificador e chave do output database_urls)."
  type = map(object({
    db_name  = string
    username = optional(string, "toggle")
  }))
  default = {
    auth      = { db_name = "auth_db" }
    flag      = { db_name = "flags_db" }
    targeting = { db_name = "targeting_db" }
  }
}

variable "rds_engine_version" {
  description = "Versão major do PostgreSQL."
  type        = string
  default     = "16"
}

variable "rds_instance_class" {
  description = "Classe das instâncias RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_storage_type" {
  description = "Tipo de armazenamento das instâncias RDS. gp3 é o padrão; a planilha de restrições do Learner Lab lista apenas gp2 para RDS — use gp2 se o apply for recusado."
  type        = string
  default     = "gp3"
}

variable "rds_allocated_storage" {
  description = "Armazenamento (GiB) de cada instância."
  type        = number
  default     = 20
}

variable "redis_node_type" {
  description = "Tipo do nó ElastiCache."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_engine_version" {
  description = "Versão do Redis."
  type        = string
  default     = "7.1"
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB usada pelo analytics-service."
  type        = string
  default     = "ToggleMasterAnalytics"
}

# ---------------------------------------------------------------------------
# Mensageria e imagens
# ---------------------------------------------------------------------------

variable "sqs_queue_name" {
  description = "Nome da fila SQS de eventos de avaliação."
  type        = string
  default     = "toggle-master-evaluations"
}

variable "ecr_image_tag_mutability" {
  description = "MUTABLE enquanto as imagens são publicadas à mão com :latest; mude para IMMUTABLE quando o CI publicar só tags de commit."
  type        = string
  default     = "MUTABLE"
}

variable "ecr_repositories" {
  description = "Repositórios ECR (um por microsserviço, no namespace togglemaster/ usado pelo código e pelo CI; devem bater com o bloco images: do kustomization)."
  type        = set(string)
  default     = ["togglemaster/auth-service", "togglemaster/flag-service", "togglemaster/targeting-service", "togglemaster/evaluation-service", "togglemaster/analytics-service"]
}
