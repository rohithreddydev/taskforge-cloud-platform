aws_region         = "us-east-1"
environment        = "prod"
kubernetes_version = "1.28"

# VPC Configuration
vpc_cidr              = "10.0.0.0/16"
private_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
public_subnet_cidrs   = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
database_subnet_cidrs = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]

# EKS Node Group Configuration
node_group_instance_types = ["t3.medium"]
node_group_desired_size   = 2
node_group_max_size       = 4
node_group_min_size       = 1
node_group_volume_size    = 50

# Enable spot instances for cost savings (optional)
enable_spot_instances = true
spot_instance_types   = ["t3.medium", "t3.large"]

# Database Configuration
db_instance_class    = "db.t3.small"
db_allocated_storage = 20
db_username          = "postgres" # Change this
