output "cluster_id" {
  description = "Identificador do cluster ElastiCache."
  value       = aws_elasticache_cluster.this.cluster_id
}

output "primary_endpoint_address" {
  description = "Hostname do nó Redis."
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "port" {
  description = "Porta do Redis."
  value       = aws_elasticache_cluster.this.cache_nodes[0].port
}

output "redis_url" {
  description = "URL de conexão no formato esperado pelo evaluation-service (redis://host:porta)."
  value       = "redis://${aws_elasticache_cluster.this.cache_nodes[0].address}:${aws_elasticache_cluster.this.cache_nodes[0].port}"
}

output "security_group_id" {
  description = "Security group do cluster Redis."
  value       = aws_security_group.this.id
}

output "subnet_group_name" {
  description = "Nome do subnet group."
  value       = aws_elasticache_subnet_group.this.name
}
