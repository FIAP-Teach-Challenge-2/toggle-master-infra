output "cluster_name" {
  description = "Cluster EKS configurado."
  value       = local.cluster_name
}

output "kubeconfig_command" {
  description = "Comando para configurar o kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}"
}

output "namespace" {
  description = "Namespace dos microsserviços."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "secret_name" {
  description = "Secret com DATABASE_URLs, REDIS_URL, AWS_SQS_URL, MASTER_KEY e SERVICE_API_KEY."
  value       = kubernetes_secret_v1.toggle_master_secrets.metadata[0].name
}

output "config_map_name" {
  description = "ConfigMap com região, tabela DynamoDB e URLs internas."
  value       = kubernetes_config_map_v1.toggle_master_config.metadata[0].name
}

output "master_key" {
  description = "MASTER_KEY do auth-service (terraform output -raw master_key)."
  value       = local.master_key
  sensitive   = true
}

output "service_api_key" {
  description = "SERVICE_API_KEY do evaluation-service (terraform output -raw service_api_key)."
  value       = local.service_api_key
  sensitive   = true
}

output "service_api_key_hash" {
  description = "SHA-256 semeado na tabela api_keys do auth_db (terraform output -raw service_api_key_hash)."
  value       = local.service_api_key_hash
  sensitive   = true
}

output "ingress_load_balancer_hostname" {
  description = "DNS do Network Load Balancer do ingress-nginx (pode aparecer só após alguns minutos; rode terraform refresh)."
  value       = try(data.kubernetes_service_v1.ingress_nginx[0].status[0].load_balancer[0].ingress[0].hostname, null)
}
