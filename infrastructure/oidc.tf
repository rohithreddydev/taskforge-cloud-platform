# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

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
            # Allow all branches (or specify main only)
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

# Output the role ARN for use in GitHub Actions
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_eks_deploy.arn
  description = "ARN of the IAM role for GitHub Actions"
}

# Add the role to EKS aws-auth ConfigMap
resource "kubernetes_config_map_v1" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.github_actions_eks_deploy.arn
        username = "github-actions"
        groups   = ["system:masters"]
      },
      {
        rolearn  = aws_iam_role.eks_node_group.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ])
  }

  depends_on = [aws_eks_cluster.main]
}