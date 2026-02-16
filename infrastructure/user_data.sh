#!/bin/bash
# user_data.sh - Bootstrap script for EKS worker nodes
# This script runs when EC2 instances launch

set -ex

# Get cluster information from Terraform template
export CLUSTER_NAME="${cluster_name}"
export CLUSTER_ENDPOINT="${cluster_endpoint}"
export CLUSTER_CA_CERT="${cluster_ca_cert}"
export CLUSTER_ID="${cluster_id}"

# Update system
yum update -y

# Install AWS CLI v2
yum install -y unzip curl jq
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

# Install SSM Agent for remote management
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/eks/${CLUSTER_NAME}/worker",
            "log_stream_name": "{instance_id}-messages",
            "timestamp_format": "%b %d %H:%M:%S"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "/aws/eks/${CLUSTER_NAME}/worker",
            "log_stream_name": "{instance_id}-cloud-init",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "/aws/eks/${CLUSTER_NAME}/worker",
            "log_stream_name": "{instance_id}-cloud-init-output",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/containers/*.log",
            "log_group_name": "/aws/eks/${CLUSTER_NAME}/containers",
            "log_stream_name": "{instance_id}-containers",
            "timestamp_format": "%Y-%m-%dT%H:%M:%S.%fZ"
          }
        ]
      }
    }
  }
}
EOF

systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Install kubectl for debugging
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Configure kernel parameters for Kubernetes
cat >> /etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Install containerd
cat > /etc/yum.repos.d/docker.repo <<EOF
[docker-ce-stable]
name=Docker CE Stable
baseurl=https://download.docker.com/linux/centos/7/x86_64/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
EOF

yum install -y containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable systemd cgroup driver
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable containerd
systemctl start containerd

# Install kubelet
cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF

yum install -y kubelet kubeadm

# Configure kubelet
cat > /etc/kubernetes/kubelet-config.json <<EOF
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "address": "0.0.0.0",
  "authentication": {
    "anonymous": {
      "enabled": false
    },
    "webhook": {
      "enabled": true,
      "cacheTTL": "2m0s"
    },
    "x509": {
      "clientCAFile": "/etc/kubernetes/pki/ca.crt"
    }
  },
  "authorization": {
    "mode": "Webhook",
    "webhook": {
      "cacheAuthorizedTTL": "5m0s",
      "cacheUnauthorizedTTL": "30s"
    }
  },
  "clusterDomain": "cluster.local",
  "clusterDNS": ["172.20.0.10"],
  "containerLogMaxSize": "10Mi",
  "containerLogMaxFiles": 5,
  "cpuManagerReconcilePeriod": "10s",
  "evictionHard": {
    "imagefs.available": "15%",
    "memory.available": "100Mi",
    "nodefs.available": "10%",
    "nodefs.inodesFree": "5%"
  },
  "evictionPressureTransitionPeriod": "5m0s",
  "fileCheckFrequency": "20s",
  "httpCheckFrequency": "20s",
  "imageMinimumGCAge": "2m0s",
  "kubeReserved": {
    "cpu": "200m",
    "memory": "256Mi"
  },
  "maxPods": 58,
  "nodeStatusReportFrequency": "5m0s",
  "nodeStatusUpdateFrequency": "10s",
  "protectKernelDefaults": true,
  "readOnlyPort": 0,
  "runtimeRequestTimeout": "2m0s",
  "serializeImagePulls": false,
  "serverTLSBootstrap": true,
  "staticPodPath": "/etc/kubernetes/manifests",
  "streamingConnectionIdleTimeout": "4h0m0s",
  "syncFrequency": "1m0s",
  "systemReserved": {
    "cpu": "200m",
    "memory": "256Mi"
  },
  "tlsCipherSuites": [
    "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305",
    "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
    "TLS_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_RSA_WITH_AES_128_GCM_SHA256"
  ]
}
EOF

# Set up kubelet environment
cat > /etc/kubernetes/kubelet.env <<EOF
KUBELET_EXTRA_ARGS="--node-ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) \
  --container-runtime=remote \
  --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
  --config=/etc/kubernetes/kubelet-config.json"
EOF

cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<EOF
[Service]
EnvironmentFile=/etc/kubernetes/kubelet.env
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_EXTRA_ARGS
Restart=always
StartLimitInterval=0
RestartSec=10
EOF

# Create necessary directories
mkdir -p /etc/kubernetes/pki
mkdir -p /var/lib/kubelet

# Write cluster CA certificate
cat > /etc/kubernetes/pki/ca.crt <<EOF
${CLUSTER_CA_CERT}
EOF

# Write bootstrap kubeconfig
cat > /var/lib/kubelet/kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/pki/ca.crt
    server: ${CLUSTER_ENDPOINT}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubelet
  name: default
current-context: default
users:
- name: kubelet
  user:
    token: $(aws eks get-token --cluster-name ${CLUSTER_NAME} --region ${aws_region} | jq -r .status.token)
EOF

# Start kubelet
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

# Tag instance with cluster name
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 create-tags \
  --resources $INSTANCE_ID \
  --tags Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=owned \
  --region ${aws_region}

# Set up node for logging and monitoring
cat > /etc/cron.hourly/disk-cleanup <<'EOF'
#!/bin/bash
# Clean up old container logs and images
docker system prune -f --filter "until=24h"
journalctl --vacuum-time=7d
find /var/log -name "*.log" -mtime +7 -delete
EOF

chmod +x /etc/cron.hourly/disk-cleanup

echo "Bootstrap completed successfully"
