# ---------------------------------------------------------------------------
# Bucket S3 para o estado remoto dos stacks bootstrap, infra e platform.
#
# O lock é feito com a flag nativa `use_lockfile = true` do backend S3
# (Terraform >= 1.10), sem necessidade de tabela DynamoDB.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"

  create_bucket_command = var.aws_region == "us-east-1" ? "aws s3api create-bucket --bucket ${local.bucket_name} --region ${var.aws_region}" : "aws s3api create-bucket --bucket ${local.bucket_name} --region ${var.aws_region} --create-bucket-configuration LocationConstraint=${var.aws_region}"
}

resource "terraform_data" "bucket" {
  input = local.bucket_name

  provisioner "local-exec" {
    command = local.create_bucket_command
  }

  # Perder este bucket significa perder o estado de toda a infraestrutura.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = local.bucket_name

  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [terraform_data.bucket]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = local.bucket_name

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  depends_on = [terraform_data.bucket]
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = local.bucket_name

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [terraform_data.bucket]
}
