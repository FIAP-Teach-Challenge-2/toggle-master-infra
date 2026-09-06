variable "name" {
  description = "Nome da fila principal."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Tempo (s) em que uma mensagem recebida fica invisível para outros consumidores."
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "Retenção das mensagens (s). Padrão: 4 dias."
  type        = number
  default     = 345600
}

variable "receive_wait_time_seconds" {
  description = "Long polling (s). O analytics-service usa WaitTimeSeconds=20."
  type        = number
  default     = 20
}

variable "max_message_size" {
  description = "Tamanho máximo da mensagem em bytes."
  type        = number
  default     = 262144
}

variable "create_dlq" {
  description = "Cria uma dead-letter queue e a associa à fila principal."
  type        = bool
  default     = true
}

variable "dlq_max_receive_count" {
  description = "Quantidade de recebimentos antes de a mensagem ir para a DLQ."
  type        = number
  default     = 5
}

variable "sqs_managed_sse_enabled" {
  description = "Criptografia em repouso gerenciada pelo SQS (sem custo de KMS)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags adicionais aplicadas às filas."
  type        = map(string)
  default     = {}
}
