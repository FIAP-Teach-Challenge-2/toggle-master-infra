# ---------------------------------------------------------------------------
# Subnet group + security group
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.identifier}-subnets" })
}

resource "aws_security_group" "this" {
  name        = "${var.identifier}-rds"
  description = "Acesso ao RDS PostgreSQL ${var.identifier}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.identifier}-rds" })
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
  description                  = "PostgreSQL a partir de security group autorizado"

  tags = var.tags
}


# ---------------------------------------------------------------------------
# Instância PostgreSQL
# ---------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted

  db_name  = var.db_name
  username = var.username
  password = var.password
  port     = var.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  multi_az               = var.multi_az
  publicly_accessible    = var.publicly_accessible

  backup_retention_period    = var.backup_retention_period
  copy_tags_to_snapshot      = true
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${var.identifier}-final"
  deletion_protection        = var.deletion_protection
  apply_immediately          = var.apply_immediately
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  tags = merge(var.tags, { Name = var.identifier })
}
