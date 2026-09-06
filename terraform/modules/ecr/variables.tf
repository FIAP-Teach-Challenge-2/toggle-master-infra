variable "repository_names" {
  description = "Nomes dos repositórios ECR (um por microsserviço)."
  type        = set(string)
}

variable "image_tag_mutability" {
  description = "MUTABLE permite sobrescrever tags como :latest; IMMUTABLE é mais seguro quando o CI publica só tags de commit."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability deve ser MUTABLE ou IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Executa scan de vulnerabilidades a cada push."
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Permite destruir o repositório mesmo com imagens."
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "AES256 ou KMS."
  type        = string
  default     = "AES256"
}

variable "lifecycle_keep_last" {
  description = "Quantidade de imagens mantidas por repositório (as mais antigas expiram)."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags adicionais aplicadas aos repositórios."
  type        = map(string)
  default     = {}
}
