terraform {
  # Mesmo bucket do stack infra, chave diferente. Lock nativo do S3.
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
