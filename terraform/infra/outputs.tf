# ---------------------------------------------------------------------------
# Conta / IAM
# ---------------------------------------------------------------------------

output "region" {
  description = "Região AWS."
  value       = var.aws_region
}

output "account_id" {
  description = "ID da conta AWS."
  value       = data.aws_caller_identity.current.account_id
}

output "lab_role_arn" {
  description = "ARN da role existente associada ao cluster e aos nós."
  value       = data.aws_iam_role.lab.arn
}

# ---------------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "ID da VPC."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Subnets públicas."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Subnets privadas."
  value       = module.networking.private_subnet_ids
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------

output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA (base64) do cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "Security group do cluster (usado pelos nós)."
  value       = module.eks.cluster_security_group_id
}

output "node_group_name" {
  description = "Nome do managed node group."
  value       = module.eks.node_group_name
}

output "kubeconfig_command" {
  description = "Comando para configurar o kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ---------------------------------------------------------------------------
# Dados
# ---------------------------------------------------------------------------

output "rds_endpoints" {
  description = "Endpoints (host:porta) das instâncias RDS, por chave."
  value       = { for key, db in module.rds : key => db.endpoint }
}

output "database_urls" {
  description = "URLs de conexão completas (contêm a senha)."
  value       = local.database_urls
  sensitive   = true
}

output "redis_endpoint" {
  description = "Hostname do Redis."
  value       = module.elasticache.primary_endpoint_address
}

output "redis_url" {
  description = "REDIS_URL do evaluation-service."
  value       = module.elasticache.redis_url
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB."
  value       = module.dynamodb.table_name
}

output "sqs_queue_url" {
  description = "URL da fila SQS (AWS_SQS_URL)."
  value       = module.sqs.queue_url
}

output "sqs_dlq_url" {
  description = "URL da dead-letter queue."
  value       = module.sqs.dlq_url
}

# ---------------------------------------------------------------------------
# Imagens
# ---------------------------------------------------------------------------

output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR por serviço."
  value       = module.ecr.repository_urls
}
