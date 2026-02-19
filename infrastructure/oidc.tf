# OIDC Provider for GitHub Actions
# Add these data sources at the top of your oidc.tf or provider.tf
data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

# Update the kubernetes provider
provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub's thumbprint

  tags = {
    Name        = "GitHub-Actions-OIDC-Provider"
    Environment = var.environment
  }
}

# IAM Role for GitHub Actions to deploy to EKS
resource "aws_iam_role" "github_actions_eks_deploy" {
  name = "GitHubActionsEKSDeployRole-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" : [
              "repo:rohithreddydev/taskforge-cloud-platform:ref:refs/heads/main",
              "repo:rohithreddydev/taskforge-cloud-platform:ref:refs/heads/develop",
              "repo:rohithreddydev/taskforge-cloud-platform:pull_request"
            ]
          }
        }
      }
    ]
  })

  tags = {
    Name        = "GitHub-Actions-EKS-Deploy-Role"
    Environment = var.environment
  }
}

# IAM Policy for EKS deployment permissions
resource "aws_iam_policy" "github_actions_eks_policy" {
  name        = "GitHubActionsEKSPolicy-${var.environment}"
  description = "Policy for GitHub Actions to deploy to EKS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "github_actions_eks_attach" {
  role       = aws_iam_role.github_actions_eks_deploy.name
  policy_arn = aws_iam_policy.github_actions_eks_policy.arn
}

# SIMPLEST FIX: Use null_resource to handle aws-auth
resource "null_resource" "configure_aws_auth" {
  depends_on = [
    aws_eks_node_group.main,
    null_resource.wait_for_cluster
  ]

  triggers = {
    cluster_name      = aws_eks_cluster.main.name
    github_actions_role = aws_iam_role.github_actions_eks_deploy.arn
    node_group_role   = aws_iam_role.eks_node_group.arn
    region            = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      echo "Configuring kubectl..."
      aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}
      
      # Create the aws-auth patch file
      cat > /tmp/aws-auth-patch.yaml << 'EOFEOF'
      data:
        mapRoles: |
          - rolearn: ${aws_iam_role.github_actions_eks_deploy.arn}
            username: github-actions
            groups:
              - system:masters
          - rolearn: ${aws_iam_role.eks_node_group.arn}
            username: system:node:{{EC2PrivateDNSName}}
            groups:
              - system:bootstrappers
              - system:nodes
      EOFEOF
      
      # Check if aws-auth exists
      if kubectl get configmap -n kube-system aws-auth &>/dev/null; then
        echo "aws-auth exists, patching..."
        kubectl patch configmap -n kube-system aws-auth --patch-file /tmp/aws-auth-patch.yaml
      else
        echo "aws-auth does not exist, creating..."
        kubectl create configmap -n kube-system aws-auth --from-literal=mapRoles=""
        kubectl patch configmap -n kube-system aws-auth --patch-file /tmp/aws-auth-patch.yaml
      fi
      
      # Clean up
      rm /tmp/aws-auth-patch.yaml
      
      echo "aws-auth configured successfully!"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "echo 'aws-auth configuration removed - manual cleanup may be required'"
  }
}

# Output the role ARN for use in GitHub Actions
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_eks_deploy.arn
  description = "ARN of the IAM role for GitHub Actions"
}