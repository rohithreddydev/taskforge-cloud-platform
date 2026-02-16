#!/bin/bash
# cleanup.sh - Clean up all resources

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Confirm cleanup
read -p "Are you sure you want to delete all resources? This action cannot be undone! (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log_info "Cleanup cancelled"
    exit 0
fi

log_info "Starting cleanup..."

# Delete Kubernetes resources
log_info "Deleting Kubernetes resources..."
kubectl delete namespace task-manager --timeout=5m || true
kubectl delete namespace monitoring --timeout=5m || true
kubectl delete namespace velero --timeout=5m || true

# Destroy Terraform infrastructure
log_info "Destroying Terraform infrastructure..."
cd infrastructure
terraform destroy -auto-approve
cd ..

# Delete ECR repositories
log_info "Deleting ECR repositories..."
aws ecr delete-repository --repository-name task-manager-backend --force || true
aws ecr delete-repository --repository-name task-manager-frontend --force || true

# Delete S3 buckets
log_info "Deleting S3 buckets..."
for bucket in $(aws s3 ls | grep task-manager | awk '{print $3}'); do
    aws s3 rb "s3://$bucket" --force
done

# Delete CloudWatch log groups
log_info "Deleting CloudWatch log groups..."
for log_group in $(aws logs describe-log-groups --log-group-name-prefix "/aws/eks/task-manager" --query 'logGroups[].logGroupName' --output text); do
    aws logs delete-log-group --log-group-name "$log_group"
done

# Clean up local files
log_info "Cleaning up local files..."
rm -rf backend/venv
rm -rf frontend/node_modules
rm -rf infrastructure/.terraform
rm -f infrastructure/terraform.tfstate*
rm -f terraform-outputs.json

log_success "Cleanup completed!"
