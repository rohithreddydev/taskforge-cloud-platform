#!/bin/bash
set -ex
cat >> /etc/eks/bootstrap.sh << 'EOF'
#!/bin/bash
/etc/eks/bootstrap.sh task-manager-eks-000gwi \
  --kubelet-extra-args '--node-labels=eks.amazonaws.com/nodegroup=task-manager-node-group,eks.amazonaws.com/sourceLaunchTemplateVersion=1'
EOF
chmod +x /etc/eks/bootstrap.sh
/etc/eks/bootstrap.sh task-manager-eks-000gwi
