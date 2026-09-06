output "repository_urls" {
  description = "Mapa nome do repositório => URL (usada nas imagens dos Deployments e no CI)."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Mapa nome do repositório => ARN."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "registry_id" {
  description = "ID do registry (conta AWS)."
  value       = try(values(aws_ecr_repository.this)[0].registry_id, null)
}
