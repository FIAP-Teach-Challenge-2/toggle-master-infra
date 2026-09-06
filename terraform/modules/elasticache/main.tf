# ---------------------------------------------------------------------------
# Subnet group + security group
# ---------------------------------------------------------------------------

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-subnets" })
}

resource "aws_security_group" "this" {
  name        = "${var.name}-redis"
  description = "Acesso ao ElastiCache Redis ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-redis" })
}

# count (e não for_each): os IDs dos SGs de origem só são conhecidos no apply.
# Sem regra de egress: o banco só responde conexões de entrada (SG é stateful).
resource "aws_vpc_security_group_ingress_rule" "from_allowed_sgs" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Redis a partir de security group autorizado"

  tags = var.tags
}


# ---------------------------------------------------------------------------
# Cluster Redis (cluster mode desabilitado, 1 nó)
# ---------------------------------------------------------------------------

resource "aws_elasticache_cluster" "this" {
  cluster_id           = var.name
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = var.num_cache_nodes
  port                 = var.port
  parameter_group_name = var.parameter_group_name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.this.id]
  apply_immediately    = var.apply_immediately

  tags = merge(var.tags, { Name = var.name })
}
