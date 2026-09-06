variable "name" {
  description = "Identificador do cluster ElastiCache (minúsculas, letras, números e hífens; máx. 50 caracteres)."
  type        = string
}

variable "engine_version" {
  description = "Versão do Redis."
  type        = string
  default     = "7.1"
}

variable "node_type" {
  description = "Tipo do nó."
  type        = string
  default     = "cache.t3.micro"
}

variable "num_cache_nodes" {
  description = "Quantidade de nós (1 para laboratório)."
  type        = number
  default     = 1
}

variable "port" {
  description = "Porta do Redis."
  type        = number
  default     = 6379
}

variable "parameter_group_name" {
  description = "Parameter group do Redis."
  type        = string
  default     = "default.redis7"
}

variable "vpc_id" {
  description = "VPC onde o security group é criado."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (privadas) do subnet group."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups autorizados a conectar na porta do Redis (ex.: SG do cluster EKS)."
  type        = list(string)
  default     = []
}

variable "apply_immediately" {
  description = "Aplica alterações imediatamente."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
