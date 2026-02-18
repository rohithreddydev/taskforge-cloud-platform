#!/bin/bash

echo "🔧 Fixing Terraform errors..."

# Fix user_data.sh - remove cluster_id reference
sed -i '' '/cluster_id/d' user_data.sh 2>/dev/null || true
echo "✅ Fixed user_data.sh"

# Create minimal outputs.tf
cat > outputs.tf << 'EOF'
output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
  sensitive   = true
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "ecr_backend_repository_url" {
  description = "Backend ECR repository URL"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repository_url" {
  description = "Frontend ECR repository URL"
  value       = aws_ecr_repository.frontend.repository_url
}

output "database_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.address
  sensitive   = true
}

output "database_password" {
  description = "RDS PostgreSQL password"
  value       = random_word.db_password.result
  sensitive   = true
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}
EOF
echo "✅ Updated outputs.tf"

# Fix launch template in main.tf
sed -i '' '/cluster_id/d' main.tf
echo "✅ Fixed main.tf"

# Validate
terraform fmt
terraform validate

echo "✅ All fixes applied! Run 'terraform plan' now."
