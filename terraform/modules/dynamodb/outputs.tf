output "table_name" {
  description = "Nome da tabela."
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN da tabela."
  value       = aws_dynamodb_table.this.arn
}

output "table_id" {
  description = "ID da tabela."
  value       = aws_dynamodb_table.this.id
}
