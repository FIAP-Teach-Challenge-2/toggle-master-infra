variable "aws_region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nome do projeto (usado em nomes e tags)."
  type        = string
  default     = "toggle-master"
}

variable "environment" {
  description = "Ambiente (usado em tags)."
  type        = string
  default     = "dev"
}

variable "bucket_name" {
  description = "Nome do bucket S3 do estado remoto. Vazio = <project>-tfstate-<account_id> (nomes de bucket são globais)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags adicionais."
  type        = map(string)
  default     = {}
}
