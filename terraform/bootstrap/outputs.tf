output "bucket_name" {
  description = "Nome do bucket S3 do estado remoto."
  value       = local.bucket_name
}

output "bucket_arn" {
  description = "ARN do bucket S3 do estado remoto."
  value       = local.bucket_arn
}

output "backend_hcl" {
  description = "Conteúdo do backend.hcl dos stacks (region/encrypt/use_lockfile já estão nos backend.tf versionados)."
  value       = "bucket = \"${local.bucket_name}\""
}
