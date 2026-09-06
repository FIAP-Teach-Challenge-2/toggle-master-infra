# ---------------------------------------------------------------------------
# Cluster EKS
#
# Este módulo NÃO cria roles ou policies de IAM (restrição do AWS Academy):
# as roles do control plane e dos nós chegam por variável (LabRole).
# ---------------------------------------------------------------------------

# Log group pré-criado para controlar a retenção e ser removido no destroy
# (se o EKS o criar sozinho, fica com retenção infinita e fora do estado).
resource "aws_cloudwatch_log_group" "cluster" {
  count = length(var.enabled_cluster_log_types) > 0 ? 1 : 0

  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = var.tags
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = var.cluster_role_arn

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  # STANDARD: a AWS faz o upgrade automático ao fim do suporte padrão em vez
  # de cobrar suporte estendido (US$ 0,60/h). O padrão da AWS é EXTENDED.
  upgrade_policy {
    support_type = var.cluster_support_type
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
    public_access_cidrs     = var.public_access_cidrs
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = merge(var.tags, { Name = var.cluster_name })

  depends_on = [aws_cloudwatch_log_group.cluster]
}

# ---------------------------------------------------------------------------
# Add-ons que precisam existir antes dos nós entrarem no cluster
# ---------------------------------------------------------------------------

resource "aws_eks_addon" "before_nodes" {
  for_each = var.addons_before_nodes

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.version
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Launch template dos nós
#
# Sem IRSA/Pod Identity (AWS Academy), os pods usam as credenciais do nó
# (LabRole) via IMDSv2. Em AL2023 um node group SEM launch template recebe
# hop limit 1, e os containers não conseguem falar com o IMDS. O launch
# template define hop limit 2 (valor recomendado pela AWS para esse caso).
# Não definir AMI, tipo de instância, security groups, IAM instance profile
# nem subnet aqui: o EKS continua gerenciando tudo isso pelo node group.
# ---------------------------------------------------------------------------

resource "aws_launch_template" "nodes" {
  name_prefix            = "${var.cluster_name}-${var.node_group_name}-"
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.node_imds_hop_limit
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-${var.node_group_name}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-${var.node_group_name}" })
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-${var.node_group_name}" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Managed node group
# ---------------------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.node_group_name
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.node_subnet_ids
  version         = var.cluster_version

  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types
  labels         = var.node_labels

  # disk_size fica no launch template (o EKS rejeita os dois juntos).
  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # O desired_size passa a ser controlado pelo autoscaler/console após a criação.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-${var.node_group_name}" })

  depends_on = [aws_eks_addon.before_nodes]
}

# ---------------------------------------------------------------------------
# Add-ons que só ficam ACTIVE com nós disponíveis (ex.: coredns)
# ---------------------------------------------------------------------------

resource "aws_eks_addon" "after_nodes" {
  for_each = var.addons_after_nodes

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = each.value.version
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}
