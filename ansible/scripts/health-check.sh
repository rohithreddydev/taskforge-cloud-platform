#!/bin/bash
# health-check.sh - Comprehensive health check script

set -e

# Configuration
CLUSTER_NAME="task-manager-eks"
NAMESPACE="task-manager"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx/yyy/zzz"
LOG_FILE="/var/log/health-check.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Send Slack notification
send_slack_notification() {
    local message=$1
    local color=${2:-"warning"}
    
    curl -X POST -H 'Content-type: application/json' \
        --data "{
            \"attachments\": [
                {
                    \"color\": \"$color\",
                    \"title\": \"Health Check Alert\",
                    \"text\": \"$message\",
                    \"footer\": \"Task Manager Health Check\",
                    \"ts\": $(date +%s)
                }
            ]
        }" \
        $SLACK_WEBHOOK_URL
}

# Check cluster status
check_cluster() {
    log "Checking cluster status..."
    
    if ! kubectl cluster-info &>/dev/null; then
        log "ERROR: Cannot connect to cluster"
        send_slack_notification "Cannot connect to EKS cluster" "danger"
        return 1
    fi
    
    log "Cluster is healthy"
    return 0
}

# Check node status
check_nodes() {
    log "Checking node status..."
    
    NOT_READY_NODES=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
    if [ $NOT_READY_NODES -gt 0 ]; then
        log "WARNING: $NOT_READY_NODES nodes are not ready"
        kubectl get nodes | grep -v "Ready" >> $LOG_FILE
        send_slack_notification "$NOT_READY_NODES nodes are not ready" "warning"
    else
        log "All nodes are ready"
    fi
}

# Check pod status
check_pods() {
    log "Checking pod status in namespace $NAMESPACE..."
    
    NOT_RUNNING_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | grep -v "Running" | grep -v "Completed" | wc -l)
    if [ $NOT_RUNNING_PODS -gt 0 ]; then
        log "WARNING: $NOT_RUNNING_PODS pods are not running"
        kubectl get pods -n $NAMESPACE | grep -v "Running" | grep -v "Completed" >> $LOG_FILE
        
        # Get details of problematic pods
        PROBLEM_PODS=$(kubectl get pods -n $NAMESPACE | grep -v "Running" | grep -v "Completed" | awk '{print $1}')
        for pod in $PROBLEM_PODS; do
            log "Describing pod $pod:"
            kubectl describe pod $pod -n $NAMESPACE | tail -20 >> $LOG_FILE
            log "Logs from pod $pod:"
            kubectl logs $pod -n $NAMESPACE --tail=20 >> $LOG_FILE
        done
        
        send_slack_notification "$NOT_RUNNING_PODS pods are not running" "warning"
    else
        log "All pods are running"
    fi
}

# Check deployments
check_deployments() {
    log "Checking deployment status..."
    
    FAILED_DEPLOYMENTS=$(kubectl get deployments -n $NAMESPACE -o json | jq -r '.items[] | select(.status.readyReplicas != .status.replicas) | .metadata.name')
    
    if [ -n "$FAILED_DEPLOYMENTS" ]; then
        log "WARNING: Some deployments are not fully ready:"
        echo "$FAILED_DEPLOYMENTS" >> $LOG_FILE
        send_slack_notification "Deployments not ready: $FAILED_DEPLOYMENTS" "warning"
    else
        log "All deployments are ready"
    fi
}

# Check services
check_services() {
    log "Checking services..."
    
    SERVICES=$(kubectl get svc -n $NAMESPACE -o name)
    for service in $SERVICES; do
        # Check if service has endpoints
        ENDPOINTS=$(kubectl get endpoints ${service#service/} -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}')
        if [ -z "$ENDPOINTS" ]; then
            log "WARNING: Service $service has no endpoints"
            send_slack_notification "Service $service has no endpoints" "warning"
        fi
    done
}

# Check application health endpoints
check_application() {
    log "Checking application health..."
    
    # Get backend service IP
    BACKEND_IP=$(kubectl get svc task-manager-backend -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
    
    # Test health endpoint
    if kubectl run test-connection --image=busybox -it --rm --restart=Never \
        -- wget -qO- http://$BACKEND_IP/health &>/dev/null; then
        log "Backend health check passed"
    else
        log "ERROR: Backend health check failed"
        send_slack_notification "Backend health check failed" "danger"
    fi
    
    # Test API endpoint
    if kubectl run test-api --image=busybox -it --rm --restart=Never \
        -- wget -qO- http://$BACKEND_IP/api/tasks &>/dev/null; then
        log "API check passed"
    else
        log "ERROR: API check failed"
        send_slack_notification "API endpoint check failed" "danger"
    fi
}

# Check resource usage
check_resources() {
    log "Checking resource usage..."
    
    # Check node resource usage
    kubectl top nodes --no-headers | while read node cpu mem; do
        cpu_percent=$(echo $cpu | sed 's/%//')
        mem_percent=$(echo $mem | sed 's/%//')
        
        if [ $cpu_percent -gt 80 ]; then
            log "WARNING: Node $node CPU usage is high: $cpu"
            send_slack_notification "Node $node CPU usage is high: $cpu" "warning"
        fi
        
        if [ $mem_percent -gt 80 ]; then
            log "WARNING: Node $node memory usage is high: $mem"
            send_slack_notification "Node $node memory usage is high: $mem" "warning"
        fi
    done
    
    # Check pod resource usage
    kubectl top pods -n $NAMESPACE --no-headers | while read pod cpu mem; do
        cpu_percent=$(echo $cpu | sed 's/%//' 2>/dev/null || echo 0)
        mem_percent=$(echo $mem | sed 's/%//' 2>/dev/null || echo 0)
        
        if [ $cpu_percent -gt 90 ] 2>/dev/null; then
            log "WARNING: Pod $pod CPU usage is high: $cpu"
        fi
        
        if [ $mem_percent -gt 90 ] 2>/dev/null; then
            log "WARNING: Pod $pod memory usage is high: $mem"
        fi
    done
}

# Check disk usage on nodes
check_disk_usage() {
    log "Checking disk usage..."
    
    NODES=$(kubectl get nodes -o name)
    for node in $NODES; do
        node_name=${node#node/}
        
        # Get disk usage via node metrics
        DISK_USAGE=$(kubectl get --raw "/api/v1/nodes/$node_name/proxy/stats/summary" | \
            jq -r '.node.fs.usedBytes / .node.fs.capacityBytes * 100' 2>/dev/null || echo 0)
        
        if (( $(echo "$DISK_USAGE > 80" | bc -l) )); then
            log "WARNING: Node $node_name disk usage is high: ${DISK_USAGE%.*}%"
            send_slack_notification "Node $node_name disk usage is high: ${DISK_USAGE%.*}%" "warning"
        fi
    done
}

# Main execution
main() {
    log "Starting health check..."
    
    check_cluster || exit 1
    check_nodes
    check_pods
    check_deployments
    check_services
    check_application
    check_resources
    check_disk_usage
    
    log "Health check completed"
}

# Run main function
main
