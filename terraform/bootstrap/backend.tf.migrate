# Renomeie este arquivo para backend.tf DEPOIS do primeiro `terraform apply`
# (o bucket precisa existir) e migre o estado do bootstrap para dentro dele:
#
#   terraform init -migrate-state -backend-config=backend.hcl
#
# A partir daí nenhum stack tem estado local. Faça commit do backend.tf.
#
# Para subir o bootstrap numa CONTA NOVA depois que o backend.tf já foi
# versionado, renomeie-o de volta para backend.tf.migrate antes do primeiro
# apply (o bucket ainda não existe lá) e repita a migração.
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
