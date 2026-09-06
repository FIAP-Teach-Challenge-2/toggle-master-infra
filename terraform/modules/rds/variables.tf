variable "identifier" {
  description = "Identificador da instância RDS (ex.: toggle-master-dev-auth)."
  type        = string
}

variable "db_name" {
  description = "Nome do banco de dados inicial criado na instância."
  type        = string
}

variable "username" {
  description = "Usuário master do banco."
  type        = string
  default     = "toggle"
}

variable "password" {
  description = "Senha do usuário master."
  type        = string
  sensitive   = true
}

variable "engine_version" {
  description = "Versão do PostgreSQL (major, ex.: 16 — o minor mais recente é escolhido automaticamente)."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "Classe da instância."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Armazenamento inicial em GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Limite do autoscaling de armazenamento em GiB (0 desabilita)."
  type        = number
  default     = 0
}

variable "storage_type" {
  description = "Tipo de armazenamento (gp3, gp2, io1)."
  type        = string
  default     = "gp3"
}

variable "vpc_id" {
  description = "VPC onde o security group da instância é criado."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (privadas) do DB subnet group."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups autorizados a conectar na porta do banco (ex.: SG do cluster EKS)."
  type        = list(string)
  default     = []
}

variable "port" {
  description = "Porta do PostgreSQL."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Habilita Multi-AZ (dobra o custo)."
  type        = bool
  default     = false
}

variable "publicly_accessible" {
  description = "Atribui IP público à instância. Mantenha false."
  type        = bool
  default     = false
}

variable "storage_encrypted" {
  description = "Criptografia em repouso."
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Dias de retenção de backups automáticos (0 desabilita)."
  type        = number
  default     = 1
}

variable "skip_final_snapshot" {
  description = "Não gera snapshot final no destroy (ambiente de laboratório)."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Impede a exclusão da instância."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Aplica alterações imediatamente em vez de esperar a janela de manutenção."
  type        = bool
  default     = true
}

variable "auto_minor_version_upgrade" {
  description = "Aplica upgrades de versão minor automaticamente."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
