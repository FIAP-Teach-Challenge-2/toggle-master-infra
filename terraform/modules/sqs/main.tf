# ---------------------------------------------------------------------------
# Dead-letter queue (opcional)
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  count = var.create_dlq ? 1 : 0

  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600 # 14 dias (máximo)
  sqs_managed_sse_enabled   = var.sqs_managed_sse_enabled

  tags = merge(var.tags, { Name = "${var.name}-dlq" })
}

# ---------------------------------------------------------------------------
# Fila principal
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "this" {
  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  max_message_size           = var.max_message_size
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled

  redrive_policy = var.create_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.dlq_max_receive_count
  }) : null

  tags = merge(var.tags, { Name = var.name })
}

# Restringe quais filas podem usar a DLQ como destino.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  count = var.create_dlq ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}
