# ---------------------------------------------------------------------------
# Dados da conta / região
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# AWS Academy: a role já existe (LabRole) e NÃO pode ser criada pelo Terraform.
# Ela é importada como data source e associada ao cluster e aos nós.
data "aws_iam_role" "lab" {
  name = var.lab_role_name
}

locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = "${local.name_prefix}-eks"
  azs          = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

# ---------------------------------------------------------------------------
# 1. Networking: VPC, subnets públicas/privadas, IGW, NAT, route tables
# ---------------------------------------------------------------------------

module "networking" {
  source = "../modules/networking"

  name                 = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = slice(var.public_subnet_cidrs, 0, var.az_count)
  private_subnet_cidrs = slice(var.private_subnet_cidrs, 0, var.az_count)
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  cluster_name         = local.cluster_name
  tags                 = var.tags
}

# ---------------------------------------------------------------------------
# 2. Cluster EKS + managed node group (ambos com a LabRole)
# ---------------------------------------------------------------------------

module "eks" {
  source = "../modules/eks"

  cluster_name              = local.cluster_name
  cluster_version           = var.eks_cluster_version
  cluster_support_type      = var.eks_cluster_support_type
  cluster_role_arn          = data.aws_iam_role.lab.arn
  node_role_arn             = data.aws_iam_role.lab.arn
  subnet_ids                = concat(module.networking.private_subnet_ids, module.networking.public_subnet_ids)
  node_subnet_ids           = var.eks_nodes_in_public_subnets ? module.networking.public_subnet_ids : module.networking.private_subnet_ids
  public_access_cidrs       = var.eks_public_access_cidrs
  authentication_mode       = var.eks_authentication_mode
  enabled_cluster_log_types = var.eks_enabled_cluster_log_types

  node_instance_types = var.eks_node_instance_types
  node_capacity_type  = var.eks_node_capacity_type
  node_disk_size      = var.eks_node_disk_size
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size

  tags = var.tags
}

# ---------------------------------------------------------------------------
# 3. Bancos de dados: 3x RDS PostgreSQL, ElastiCache Redis, DynamoDB
# ---------------------------------------------------------------------------

resource "random_password" "rds" {
  for_each = var.rds_databases

  length  = 24
  special = false # evita caracteres que precisariam de URL-encoding na DATABASE_URL
}

module "rds" {
  source   = "../modules/rds"
  for_each = var.rds_databases

  identifier        = "${local.name_prefix}-${each.key}"
  db_name           = each.value.db_name
  username          = each.value.username
  password          = random_password.rds[each.key].result
  engine_version    = var.rds_engine_version
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  storage_type      = var.rds_storage_type

  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  tags = var.tags
}

module "elasticache" {
  source = "../modules/elasticache"

  name           = "${local.name_prefix}-redis"
  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type

  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  tags = var.tags
}

module "dynamodb" {
  source = "../modules/dynamodb"

  table_name = var.dynamodb_table_name
  hash_key   = "event_id"
  tags       = var.tags
}

# ---------------------------------------------------------------------------
# 4. Mensageria: fila SQS (+ DLQ)
# ---------------------------------------------------------------------------

module "sqs" {
  source = "../modules/sqs"

  name = var.sqs_queue_name
  tags = var.tags
}

# ---------------------------------------------------------------------------
# 5. Repositórios ECR (um por microsserviço)
# ---------------------------------------------------------------------------

module "ecr" {
  source = "../modules/ecr"

  repository_names     = var.ecr_repositories
  image_tag_mutability = var.ecr_image_tag_mutability
  tags                 = var.tags
}

# ---------------------------------------------------------------------------
# URLs de conexão (consumidas pelo stack platform via terraform_remote_state)
# ---------------------------------------------------------------------------

locals {
  database_urls = {
    for key, db in module.rds :
    key => "postgres://${db.username}:${random_password.rds[key].result}@${db.address}:${db.port}/${db.db_name}?sslmode=require"
  }
}
