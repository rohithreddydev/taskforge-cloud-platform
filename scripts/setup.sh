#!/bin/bash
# setup.sh - Complete setup script for Task Manager project

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="task-manager"
AWS_REGION="us-east-1"
EKS_CLUSTER_NAME="task-manager-eks"
BACKEND_REPO_NAME="task-manager-backend"
FRONTEND_REPO_NAME="task-manager-frontend"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    log_success "AWS CLI found: $(aws --version)"
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Please install it first."
        exit 1
    fi
    log_success "Terraform found: $(terraform version | head -n1)"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install it first."
        exit 1
    fi
    log_success "kubectl found: $(kubectl version --client --short | cut -d' ' -f3)"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install it first."
        exit 1
    fi
    log_success "Docker found: $(docker --version)"
    
    # Check Helm
    if ! command -v helm &> /dev/null; then
        log_warning "Helm not found. Will install later."
    else
        log_success "Helm found: $(helm version --short)"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_success "AWS credentials valid for account: $ACCOUNT_ID"
}

# Setup directory structure
setup_directories() {
    log_info "Setting up project directories..."
    
    mkdir -p backend frontend infrastructure kubernetes monitoring ansible scripts .github/workflows
    log_success "Directory structure created"
}

# Setup Python virtual environment
setup_python_env() {
    log_info "Setting up Python virtual environment..."
    
    cd backend
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    cd ..
    
    log_success "Python virtual environment created"
}

# Build and test locally
build_local() {
    log_info "Building and testing locally..."
    
    # Run backend tests
    cd backend
    source venv/bin/activate
    pytest tests/ -v --cov=. --cov-report=term
    cd ..
    
    # Build frontend
    cd frontend
    npm install
    npm run build
    cd ..
    
    log_success "Local build completed"
}

# Initialize Terraform
init_terraform() {
    log_info "Initializing Terraform..."
    
    cd infrastructure
    
    # Create S3 bucket for Terraform state if it doesn't exist
    BUCKET_NAME="task-manager-terraform-state-$(date +%s)"
    if ! aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        aws s3 mb "s3://$BUCKET_NAME" --region $AWS_REGION
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        log_success "Created S3 bucket for Terraform state: $BUCKET_NAME"
    fi
    
    # Create DynamoDB table for state locking
    if ! aws dynamodb describe-table --table-name terraform-state-lock &> /dev/null; then
        aws dynamodb create-table \
            --table-name terraform-state-lock \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST
        log_success "Created DynamoDB table for state locking"
    fi
    
    # Initialize Terraform
    terraform init
    
    cd ..
    
    log_success "Terraform initialized"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd infrastructure
    
    # Create terraform.tfvars
    cat > terraform.tfvars <<EOF
aws_region = "$AWS_REGION"
environment = "dev"
kubernetes_version = "1.28"
node_group_instance_types = ["t3.medium"]
node_group_desired_size = 2
node_group_max_size = 4
node_group_min_size = 1
enable_spot_instances = true
EOF
    
    # Plan and apply
    terraform plan -out=tfplan
    terraform apply tfplan
    
    # Get outputs
    terraform output -json > ../terraform-outputs.json
    
    cd ..
    
    log_success "Infrastructure deployed"
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl..."
    
    aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
    
    # Test connection
    kubectl get nodes
    
    log_success "kubectl configured"
}

# Build and push Docker images
build_and_push_images() {
    log_info "Building and pushing Docker images..."
    
    # Get ECR login
    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    
    # Build and push backend
    cd backend
    docker build -t $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$BACKEND_REPO_NAME:latest .
    docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$BACKEND_REPO_NAME:latest
    cd ..
    
    # Build and push frontend
    cd frontend
    docker build -t $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$FRONTEND_REPO_NAME:latest .
    docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$FRONTEND_REPO_NAME:latest
    cd ..
    
    log_success "Images built and pushed to ECR"
}

# Deploy to Kubernetes
deploy_to_kubernetes() {
    log_info "Deploying to Kubernetes..."
    
    # Create namespace
    kubectl apply -f kubernetes/namespace.yaml
    
    # Create secrets
    kubectl create secret generic task-manager-secrets \
        --namespace task-manager \
        --from-literal=database-url="postgresql://postgres:password@$DB_HOST:5432/taskdb" \
        --from-literal=redis-url="redis://$REDIS_HOST:6379/0" \
        --from-literal=secret-key="$(openssl rand -base64 32)" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Update image in deployment files
    sed -i "s|<aws-account-id>|$ACCOUNT_ID|g" kubernetes/backend-deployment.yaml
    sed -i "s|<aws-account-id>|$ACCOUNT_ID|g" kubernetes/frontend-deployment.yaml
    sed -i "s|us-east-1|$AWS_REGION|g" kubernetes/backend-deployment.yaml
    
    # Apply configurations
    kubectl apply -f kubernetes/configmap.yaml
    kubectl apply -f kubernetes/backend-deployment.yaml
    kubectl apply -f kubernetes/backend-service.yaml
    kubectl apply -f kubernetes/frontend-deployment.yaml
    kubectl apply -f kubernetes/frontend-service.yaml
    kubectl apply -f kubernetes/hpa.yaml
    kubectl apply -f kubernetes/pdb.yaml
    
    # Wait for deployments
    kubectl rollout status deployment/task-manager-backend -n task-manager --timeout=5m
    kubectl rollout status deployment/task-manager-frontend -n task-manager --timeout=5m
    
    # Apply ingress (if domain is configured)
    if [ -n "$DOMAIN_NAME" ]; then
        kubectl apply -f kubernetes/ingress.yaml
    fi
    
    log_success "Application deployed to Kubernetes"
}

# Setup monitoring
setup_monitoring() {
    log_info "Setting up monitoring stack..."
    
    # Add Helm repositories
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Prometheus and Grafana
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --set grafana.enabled=true \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --values - <<EOF
grafana:
  adminPassword: admin
  service:
    type: LoadBalancer
  additionalDataSources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-operated:9090
      access: proxy
      isDefault: true
prometheus:
  prometheusSpec:
    retention: 15d
    resources:
      requests:
        memory: 2Gi
        cpu: 500m
      limits:
        memory: 4Gi
        cpu: 1000m
alertmanager:
  enabled: true
  config:
    global:
      slack_api_url: $SLACK_WEBHOOK_URL
    route:
      group_by: ['alertname', 'cluster', 'service']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'slack-notifications'
    receivers:
    - name: 'slack-notifications'
      slack_configs:
      - channel: '#alerts'
        title: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}\n{{ end }}'
EOF
    
    # Apply custom Prometheus config
    kubectl apply -f monitoring/prometheus-config.yaml
    
    # Import dashboard
    kubectl create configmap task-manager-dashboard \
        --namespace monitoring \
        --from-file=monitoring/grafana-dashboards/task-manager-dashboard.json \
        --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl label configmap task-manager-dashboard \
        --namespace monitoring \
        grafana_dashboard=1
    
    log_success "Monitoring stack deployed"
}

# Setup backup
setup_backup() {
    log_info "Setting up automated backups..."
    
    # Install Velero
    helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
    helm repo update
    
    # Create S3 bucket for backups
    BACKUP_BUCKET="task-manager-backups-$(date +%s)"
    aws s3 mb "s3://$BACKUP_BUCKET" --region $AWS_REGION
    
    # Install Velero
    helm upgrade --install velero vmware-tanzu/velero \
        --namespace velero \
        --create-namespace \
        --set configuration.provider=aws \
        --set configuration.backupStorageLocation.name=default \
        --set configuration.backupStorageLocation.bucket=$BACKUP_BUCKET \
        --set configuration.backupStorageLocation.config.region=$AWS_REGION \
        --set initContainers[0].name=velero-plugin-for-aws \
        --set initContainers[0].image=velero/velero-plugin-for-aws:v1.7.0 \
        --set initContainers[0].volumeMounts[0].mountPath=/target \
        --set initContainers[0].volumeMounts[0].name=plugins
    
    # Create backup schedule
    cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"
  template:
    includedNamespaces:
    - task-manager
    ttl: 168h
EOF
    
    log_success "Backup system configured"
}

# Setup CI/CD secrets
setup_cicd_secrets() {
    log_info "Setting up CI/CD secrets..."
    
    # Create GitHub secrets
    if command -v gh &> /dev/null; then
        gh secret set AWS_ACCESS_KEY_ID --body "$AWS_ACCESS_KEY_ID"
        gh secret set AWS_SECRET_ACCESS_KEY --body "$AWS_SECRET_ACCESS_KEY"
        gh secret set AWS_REGION --body "$AWS_REGION"
        gh secret set SLACK_WEBHOOK --body "$SLACK_WEBHOOK_URL"
        gh secret set SONAR_TOKEN --body "$SONAR_TOKEN"
        gh secret set SNYK_TOKEN --body "$SNYK_TOKEN"
        
        log_success "GitHub secrets configured"
    else
        log_warning "GitHub CLI not found. Please manually configure secrets:"
        echo "  - AWS_ACCESS_KEY_ID"
        echo "  - AWS_SECRET_ACCESS_KEY"
        echo "  - AWS_REGION"
        echo "  - SLACK_WEBHOOK"
        echo "  - SONAR_TOKEN"
        echo "  - SNYK_TOKEN"
    fi
}

# Run smoke tests
run_smoke_tests() {
    log_info "Running smoke tests..."
    
    # Get service endpoints
    BACKEND_SERVICE=$(kubectl get svc task-manager-backend -n task-manager -o jsonpath='{.spec.clusterIP}')
    
    # Test health endpoint
    echo "Testing health endpoint..."
    if kubectl run test --image=busybox -it --rm --restart=Never \
        -- wget -qO- http://$BACKEND_SERVICE/health &>/dev/null; then
        log_success "Health check passed"
    else
        log_error "Health check failed"
        exit 1
    fi
    
    # Test API
    echo "Testing API..."
    if kubectl run test --image=busybox -it --rm --restart=Never \
        -- wget -qO- http://$BACKEND_SERVICE/api/tasks &>/dev/null; then
        log_success "API check passed"
    else
        log_error "API check failed"
        exit 1
    fi
    
    # Get frontend service
    FRONTEND_SERVICE=$(kubectl get svc task-manager-frontend -n task-manager -o jsonpath='{.spec.clusterIP}')
    
    # Test frontend
    echo "Testing frontend..."
    if kubectl run test --image=busybox -it --rm --restart=Never \
        -- wget -qO- http://$FRONTEND_SERVICE &>/dev/null; then
        log_success "Frontend check passed"
    else
        log_error "Frontend check failed"
        exit 1
    fi
    
    log_success "All smoke tests passed"
}

# Main function
main() {
    log_info "Starting Task Manager DevOps Project Setup"
    echo "================================================"
    
    # Run all setup steps
    check_prerequisites
    setup_directories
    setup_python_env
    build_local
    init_terraform
    deploy_infrastructure
    configure_kubectl
    build_and_push_images
    deploy_to_kubernetes
    setup_monitoring
    setup_backup
    setup_cicd_secrets
    run_smoke_tests
    
    echo "================================================"
    log_success "Task Manager DevOps Project Setup Complete!"
    
    # Print summary
    echo ""
    echo "=== Deployment Summary ==="
    echo "Application URL: https://app.task-manager.com"
    echo "API URL: https://api.task-manager.com"
    echo "Grafana URL: http://$(kubectl get svc -n monitoring monitoring-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
    echo "Prometheus URL: http://$(kubectl get svc -n monitoring prometheus-operated -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):9090"
    echo ""
    echo "To view pods: kubectl get pods -n task-manager"
    echo "To view logs: kubectl logs -n task-manager deployment/task-manager-backend"
    echo "To run health check: ./scripts/health-check.sh"
}

# Run main function
main "$@"
