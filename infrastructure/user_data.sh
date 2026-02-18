#!/bin/bash
set -ex

# Log all output for debugging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting EKS node bootstrap at $(date)"

# Get cluster information from Terraform template
export CLUSTER_NAME="${cluster_name}"
export CLUSTER_ENDPOINT="${cluster_endpoint}"
export CLUSTER_CA_CERT="${cluster_ca_cert}"
export API_SERVER_URL="${cluster_endpoint}"

echo "CLUSTER_NAME: $CLUSTER_NAME"
echo "CLUSTER_ENDPOINT: $CLUSTER_ENDPOINT"

# Update system
yum update -y

# Install AWS CLI v2
yum install -y unzip curl jq
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

# Install SSM Agent for remote debugging
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Configure kernel parameters for Kubernetes
cat >> /etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.overcommit_memory = 1
kernel.panic = 10
kernel.panic_on_oops = 1
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
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable containerd
systemctl start containerd
systemctl status containerd

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
mkdir -p /etc/kubernetes/pki
mkdir -p /var/lib/kubelet

# Write cluster CA certificate
cat > /etc/kubernetes/pki/ca.crt <<EOF
${cluster_ca_cert}
EOF

# Write kubeconfig for kubelet
cat > /var/lib/kubelet/kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/pki/ca.crt
    
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
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: /usr/bin/aws
      args:
      - eks
      - get-token
      - --cluster-name
      - ${cluster_name}
      - --region
      - us-east-1
EOF

# Configure kubelet extra args
cat > /etc/kubernetes/kubelet.env <<EOF
KUBELET_EXTRA_ARGS="--node-ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4) \
  --container-runtime=remote \
  --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
  --kubeconfig=/var/lib/kubelet/kubeconfig"
EOF

# Configure kubelet service
mkdir -p /etc/systemd/system/kubelet.service.d
cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<EOF
[Service]
EnvironmentFile=/etc/kubernetes/kubelet.env
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_EXTRA_ARGS
Restart=always
StartLimitInterval=0
RestartSec=10
EOF

# Start kubelet
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

# Verify kubelet is running
sleep 10
systemctl status kubelet --no-pager

# Tag instance with cluster name
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 create-tags \
  --resources $INSTANCE_ID \
  --tags Key=kubernetes.io/cluster/${cluster_name},Value=owned \
  --region us-east-1

echo "Bootstrap completed successfully at $(date)"