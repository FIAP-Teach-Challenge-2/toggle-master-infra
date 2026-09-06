terraform {
  # Backend remoto em S3 com lock nativo (use_lockfile, Terraform >= 1.10):
  # dispensa a tabela DynamoDB de lock. Só o nome do bucket (específico da
  # conta) fica fora do versionamento, em backend.hcl:
  #
  #   terraform init -backend-config=backend.hcl
  #
  backend "s3" {
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
