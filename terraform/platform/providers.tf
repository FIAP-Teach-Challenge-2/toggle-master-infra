provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project
        Environment = var.environment
        ManagedBy   = "terraform"
        Stack       = "platform"
      },
      var.tags,
    )
  }
}

data "aws_caller_identity" "current" {}

# Outputs do stack infra (nome do cluster, URLs de banco/Redis/SQS, tabela),
# lidos do mesmo bucket S3 que guarda os estados. Nenhum serviço extra.
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = var.infra_state_key
    region = var.aws_region
  }
}

# Endpoint e CA vêm da API do EKS; o token é obtido na hora via
# `aws eks get-token` com as credenciais atuais (no Academy, o mesmo principal
# que rodou o infra e recebeu cluster-admin na criação do cluster).
data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
    }
  }
}
