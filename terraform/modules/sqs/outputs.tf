output "queue_url" {
  description = "URL da fila principal (valor da env AWS_SQS_URL)."
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN da fila principal."
  value       = aws_sqs_queue.this.arn
}

output "queue_name" {
  description = "Nome da fila principal."
  value       = aws_sqs_queue.this.name
}

output "dlq_url" {
  description = "URL da dead-letter queue (null se não criada)."
  value       = var.create_dlq ? aws_sqs_queue.dlq[0].url : null
}

output "dlq_arn" {
  description = "ARN da dead-letter queue (null se não criada)."
  value       = var.create_dlq ? aws_sqs_queue.dlq[0].arn : null
}
