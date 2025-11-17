output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.cluster.id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.cluster.arn
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.cluster.endpoint
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}
output "oidc_provider_arn" {
  description = "OIDC provider ARN"
  value       = var.create_oidc_provider ? aws_iam_openid_connect_provider.eks[0].arn : null
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL"
  value       = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}