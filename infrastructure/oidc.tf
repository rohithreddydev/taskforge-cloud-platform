# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # Note: As of 2024, thumbprint is no longer required for GitHub OIDC [citation:5]
  # AWS automatically validates the certificate using its root CA store

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
            # Restrict to your GitHub repo and main branch
            "token.actions.githubusercontent.com:sub" : "repo:rohithreddydev/taskforge-cloud-platform:ref:refs/heads/main"
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
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = aws_eks_cluster.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = [
          aws_ecr_repository.backend.arn,
          aws_ecr_repository.frontend.arn
        ]
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

# Output the role ARN for use in GitHub Actions
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_eks_deploy.arn
  description = "ARN of the IAM role for GitHub Actions"
}
