variable "aws_region" {
  description = "Região AWS (a mesma do stack infra)."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nome do projeto (o mesmo do stack infra)."
  type        = string
  default     = "toggle-master"
}

variable "environment" {
  description = "Ambiente (o mesmo do stack infra)."
  type        = string
  default     = "dev"
}

variable "state_bucket" {
  description = "Bucket S3 onde está o estado do stack infra. Vazio = <project>-tfstate-<account_id> (convenção do bootstrap)."
  type        = string
  default     = ""
}

variable "infra_state_key" {
  description = "Chave do estado do stack infra dentro do bucket."
  type        = string
  default     = "infra/terraform.tfstate"
}

variable "namespace" {
  description = "Namespace Kubernetes dos microsserviços."
  type        = string
  default     = "toggle-master"
}

variable "master_key" {
  description = "MASTER_KEY do auth-service. Vazio = gerada aleatoriamente e mantida no estado."
  type        = string
  default     = ""
  sensitive   = true
}

variable "service_api_key" {
  description = "SERVICE_API_KEY usada pelo evaluation-service (formato tm_key_...). Vazio = gerada aleatoriamente; o hash SHA-256 é semeado no auth_db pelo Job auth-db-init."
  type        = string
  default     = ""
  sensitive   = true
}

variable "install_metrics_server" {
  description = "Instala o metrics-server via Helm (necessário para o HPA)."
  type        = bool
  default     = true
}

variable "metrics_server_chart_version" {
  description = "Versão do chart metrics-server (fixada para reprodutibilidade)."
  type        = string
  default     = "3.13.1"
}

variable "install_ingress_nginx" {
  description = "Instala o ingress-nginx via Helm (cria o Network Load Balancer de entrada)."
  type        = bool
  default     = true
}

variable "ingress_nginx_chart_version" {
  description = "Versão do chart ingress-nginx. O projeto foi aposentado em mar/2026 (repositório arquivado, sem correções de segurança); 4.15.1 é o último release e suporta Kubernetes até 1.35."
  type        = string
  default     = "4.15.1"
}

variable "tags" {
  description = "Tags adicionais (recursos AWS)."
  type        = map(string)
  default     = {}
}
