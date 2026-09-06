output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "cluster_id" {
  description = "ID do cluster EKS."
  value       = aws_eks_cluster.this.id
}

output "cluster_arn" {
  description = "ARN do cluster EKS."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Certificado (base64) da CA do cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Versão do Kubernetes do cluster."
  value       = aws_eks_cluster.this.version
}

output "cluster_platform_version" {
  description = "Versão de plataforma do EKS."
  value       = aws_eks_cluster.this.platform_version
}

output "cluster_security_group_id" {
  description = "Security group criado pelo EKS e compartilhado entre control plane e nós do managed node group. Use-o para liberar acesso a RDS/Redis."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_issuer_url" {
  description = "URL do issuer OIDC do cluster (informativo; sem IRSA no AWS Academy)."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "node_group_name" {
  description = "Nome do managed node group."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_arn" {
  description = "ARN do managed node group."
  value       = aws_eks_node_group.this.arn
}

output "node_launch_template_id" {
  description = "ID do launch template dos nós (IMDS hop limit, disco)."
  value       = aws_launch_template.nodes.id
}

output "node_group_status" {
  description = "Status do managed node group."
  value       = aws_eks_node_group.this.status
}
