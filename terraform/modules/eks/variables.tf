variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "cluster_version" {
  description = "Versão do Kubernetes do cluster. Consulte `aws eks describe-cluster-versions` para as versões em suporte padrão (fora dele o control plane custa 6x)."
  type        = string
  default     = "1.35"
}

variable "cluster_support_type" {
  description = "Política de upgrade do control plane: STANDARD (auto-upgrade ao fim do suporte padrão, sem custo de suporte estendido) ou EXTENDED (padrão da AWS, US$ 0,60/h após o fim do suporte padrão)."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.cluster_support_type)
    error_message = "cluster_support_type deve ser STANDARD ou EXTENDED."
  }
}

variable "cluster_role_arn" {
  description = "ARN da IAM role usada pelo control plane do EKS. No AWS Academy, use a LabRole existente (nenhuma role é criada por este módulo)."
  type        = string
}

variable "node_role_arn" {
  description = "ARN da IAM role usada pelos nós do managed node group. No AWS Academy, use a LabRole existente."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets onde o EKS cria as ENIs do control plane (recomendado: privadas + públicas, em pelo menos 2 AZs)."
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets onde os nós do node group são lançados."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expõe o endpoint da API do Kubernetes publicamente (necessário para rodar kubectl/Terraform de fora da VPC)."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Habilita o acesso ao endpoint da API por dentro da VPC."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint público da API."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "authentication_mode" {
  description = "Modo de autenticação do cluster: API, API_AND_CONFIG_MAP ou CONFIG_MAP."
  type        = string
  default     = "API_AND_CONFIG_MAP"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode deve ser API, API_AND_CONFIG_MAP ou CONFIG_MAP."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Concede cluster-admin ao principal IAM que cria o cluster (o usuário/role que roda o terraform apply)."
  type        = bool
  default     = true
}

variable "enabled_cluster_log_types" {
  description = "Tipos de log do control plane enviados ao CloudWatch (api, audit, authenticator, controllerManager, scheduler). Vazio = desabilitado."
  type        = list(string)
  default     = []
}

variable "cloudwatch_log_retention_days" {
  description = "Retenção (dias) do log group do control plane."
  type        = number
  default     = 7
}

variable "node_group_name" {
  description = "Nome do managed node group."
  type        = string
  default     = "default"
}

variable "node_instance_types" {
  description = "Tipos de instância EC2 dos nós."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_ami_type" {
  description = "Tipo de AMI dos nós (ex.: AL2023_x86_64_STANDARD, AL2023_ARM_64_STANDARD)."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_capacity_type" {
  description = "ON_DEMAND ou SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type deve ser ON_DEMAND ou SPOT."
  }
}

variable "node_disk_size" {
  description = "Tamanho do disco raiz (gp3, criptografado) dos nós, em GiB. Definido no launch template. Mínimo 20 (tamanho do snapshot da AMI EKS AL2023)."
  type        = number
  default     = 20

  validation {
    condition     = var.node_disk_size >= 20
    error_message = "node_disk_size deve ser >= 20 GiB (tamanho do snapshot raiz da AMI EKS AL2023)."
  }
}

variable "node_imds_hop_limit" {
  description = "HttpPutResponseHopLimit do IMDSv2 nos nós. 2 permite que os pods usem as credenciais da role do nó (necessário sem IRSA); 1 bloqueia."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Quantidade desejada de nós."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade mínima de nós."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade máxima de nós."
  type        = number
  default     = 3
}

variable "node_labels" {
  description = "Labels Kubernetes aplicadas aos nós."
  type        = map(string)
  default     = {}
}

variable "addons_before_nodes" {
  description = "Add-ons do EKS instalados antes do node group (rede e proxy)."
  type = map(object({
    version              = optional(string)
    configuration_values = optional(string)
  }))
  default = {
    vpc-cni    = {}
    kube-proxy = {}
  }
}

variable "addons_after_nodes" {
  description = "Add-ons do EKS instalados depois do node group (precisam de nós para ficar ACTIVE)."
  type = map(object({
    version              = optional(string)
    configuration_values = optional(string)
  }))
  default = {
    coredns = {}
  }
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
