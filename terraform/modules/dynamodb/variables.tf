variable "table_name" {
  description = "Nome da tabela."
  type        = string
}

variable "hash_key" {
  description = "Nome do atributo da partition key."
  type        = string
  default     = "event_id"
}

variable "hash_key_type" {
  description = "Tipo do atributo da partition key (S, N ou B)."
  type        = string
  default     = "S"

  validation {
    condition     = contains(["S", "N", "B"], var.hash_key_type)
    error_message = "hash_key_type deve ser S, N ou B."
  }
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST (sob demanda) ou PROVISIONED."
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode deve ser PAY_PER_REQUEST ou PROVISIONED."
  }
}

variable "read_capacity" {
  description = "RCUs (apenas com billing_mode = PROVISIONED)."
  type        = number
  default     = 1
}

variable "write_capacity" {
  description = "WCUs (apenas com billing_mode = PROVISIONED)."
  type        = number
  default     = 1
}

variable "point_in_time_recovery_enabled" {
  description = "Habilita PITR (backup contínuo)."
  type        = bool
  default     = false
}

variable "deletion_protection_enabled" {
  description = "Impede a exclusão da tabela."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags adicionais aplicadas à tabela."
  type        = map(string)
  default     = {}
}
