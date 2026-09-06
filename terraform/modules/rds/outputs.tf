output "instance_id" {
  description = "Identificador da instância."
  value       = aws_db_instance.this.id
}

output "instance_arn" {
  description = "ARN da instância."
  value       = aws_db_instance.this.arn
}

output "address" {
  description = "Hostname da instância."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Porta da instância."
  value       = aws_db_instance.this.port
}

output "endpoint" {
  description = "Endpoint no formato host:porta."
  value       = aws_db_instance.this.endpoint
}

output "db_name" {
  description = "Nome do banco inicial."
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "Usuário master."
  value       = aws_db_instance.this.username
}

output "security_group_id" {
  description = "Security group da instância."
  value       = aws_security_group.this.id
}

output "db_subnet_group_name" {
  description = "Nome do DB subnet group."
  value       = aws_db_subnet_group.this.name
}
