terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Este stack cria o bucket que guarda o estado de todos os stacks. Por isso
  # o PRIMEIRO apply usa estado local; logo depois o estado é migrado para o
  # próprio bucket (backend.tf.migrate -> backend.tf + init -migrate-state).
}
