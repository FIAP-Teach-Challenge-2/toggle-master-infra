variable "name" {
  description = "Prefixo usado no nome dos recursos de rede (ex.: toggle-master-dev)."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Zonas de disponibilidade usadas (uma subnet pública e uma privada por AZ)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Informe pelo menos 2 zonas de disponibilidade (exigência do EKS)."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas, na mesma ordem e quantidade de azs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs deve ter exatamente um CIDR por AZ."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas, na mesma ordem e quantidade de azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs deve ter exatamente um CIDR por AZ."
  }
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway para dar saída à internet às subnets privadas (necessário para nós EKS privados baixarem imagens do ECR)."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Usa um único NAT Gateway compartilhado (mais barato) em vez de um por AZ."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Nome do cluster EKS; usado na tag kubernetes.io/cluster/<name> das subnets para descoberta de subnets pelos load balancers."
  type        = string
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
