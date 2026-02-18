# main.tf - Complete EKS Infrastructure (FREE TIER OPTIMIZED)
# This file defines all AWS resources needed for the Task Manager application
# All resources are selected to stay within AWS Free Tier limits

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Backend configuration - store state in S3
  backend "s3" {
    bucket         = "taskforge-terraform-state-1771362137"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "TaskManager"
      ManagedBy   = "Terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Random suffix for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# VPC Module - Free Tier compatible (minimal setup)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "task-manager-vpc-${random_string.suffix.result}"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # NAT Gateway - EXPENSIVE! Using single NAT gateway to minimize cost
  enable_nat_gateway   = true
  single_nat_gateway   = true # Saves money by using only one NAT gateway
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags for EKS
  private_subnet_tags = {
    "kubernetes.io/cluster/task-manager-eks-${random_string.suffix.result}" = "shared"
    "kubernetes.io/role/internal-elb"                                       = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/task-manager-eks-${random_string.suffix.result}" = "shared"
    "kubernetes.io/role/elb"                                                = "1"
  }

  tags = {
    Environment = var.environment
  }
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster" {
  name = "task-manager-eks-cluster-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Cluster - Free Tier (EKS control plane is free, you pay for worker nodes)
resource "aws_eks_cluster" "main" {
  name     = "task-manager-eks-${random_string.suffix.result}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.28" # Using stable version

  vpc_config {
    subnet_ids              = concat(module.vpc.private_subnets, module.vpc.public_subnets)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  # Enable minimal logging to save costs
  enabled_cluster_log_types = ["api"] # Only enable API logs to reduce CloudWatch costs

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "task-manager-eks"
  }
}

# EKS Node Group IAM Role
resource "aws_iam_role" "eks_node_group" {
  name = "task-manager-eks-node-group-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# Add SSM policy for debugging
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_node_group.name
}

# Security group for EKS nodes
resource "aws_security_group" "eks_nodes" {
  name        = "task-manager-eks-nodes-sg-${random_string.suffix.result}"
  description = "Security group for EKS worker nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Node to node communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "Cluster to node communication"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  ingress {
    description = "kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task-manager-eks-nodes-sg"
  }
}

# Data source for latest EKS optimized AMI
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/1.28/amazon-linux-2/recommended/image_id"
}

# Launch template for node group
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "task-manager-node-template-"
  image_id    = data.aws_ssm_parameter.eks_ami.value

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp2"
      delete_on_termination = true
      encrypted             = false
    }
  }

  monitoring {
    enabled = false
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "task-manager-eks-node"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cluster_name     = aws_eks_cluster.main.name
    cluster_endpoint = aws_eks_cluster.main.endpoint
    cluster_ca_cert  = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  }))
}

# EKS Node Group - Using t3.micro (Free Tier eligible)
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "task-manager-node-group-${random_string.suffix.result}"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = module.vpc.private_subnets

  # t3.micro is Free Tier eligible (750 hours/month)
  instance_types = ["t3.micro"]

  scaling_config {
    desired_size = 1 # Single node to save costs
    max_size     = 2 # Allow scaling but keep minimal
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    name    = aws_launch_template.eks_nodes.name
    version = "$Latest"
  }

  tags = {
    Name = "task-manager-node-group"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only
  ]
}

# ECR Repositories - Free tier (500MB storage included)
resource "aws_ecr_repository" "backend" {
  name                 = "task-manager-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false # Disable scanning to save costs
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "task-manager-backend"
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "task-manager-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false # Disable scanning to save costs
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "task-manager-frontend"
  }
}

# RDS PostgreSQL instance - Free Tier
resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_db_subnet_group" "main" {
  name       = "task-manager-db-subnet-group-${random_string.suffix.result}"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "task-manager-db-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "task-manager-rds-sg-${random_string.suffix.result}"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL access from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task-manager-rds-sg"
  }
}

# RDS Instance - Free Tier Compatible - FIXED VERSION
resource "aws_db_instance" "postgres" {
  identifier = "task-manager-db-${random_string.suffix.result}"

  engine         = "postgres"
  engine_version = "17.6"              # FIXED: Using stable PostgreSQL 15.7 (exists)
  instance_class = "db.t4g.micro"      # Free tier eligible

  allocated_storage     = 20           # Free tier: 20GB
  max_allocated_storage = 0            # Disable autoscaling for free tier
  storage_encrypted     = false        # Free tier doesn't support encryption
  storage_type          = "gp2"        # gp2 is included in free tier

  db_name  = "taskdb"
  username = "postgres"
  password = random_password.db_password.result

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  # Free tier compatible settings
  backup_retention_period = 0           # Disable backups for free tier
  skip_final_snapshot     = true
  deletion_protection     = false
  publicly_accessible     = false

  tags = {
    Name = "task-manager-postgres"
  }
}