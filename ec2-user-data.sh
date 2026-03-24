#!/bin/bash
set -e
exec > /var/log/user-data.log 2>&1

LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-7}
APP_DIR="/home/ubuntu/sample-app"

echo "==> [1/7] System update..."
apt-get update -y
apt-get install -y curl git unzip ca-certificates gnupg lsb-release

# ── Docker ────────────────────────────────────────────────────────────────────
echo "==> [2/7] Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# ── kubectl ───────────────────────────────────────────────────────────────────
echo "==> [3/7] Installing kubectl..."
curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# ── Helm ──────────────────────────────────────────────────────────────────────
echo "==> [4/7] Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── Minikube ──────────────────────────────────────────────────────────────────
echo "==> [5/7] Installing Minikube..."
curl -fsSL https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  -o /usr/local/bin/minikube
chmod +x /usr/local/bin/minikube

# # ── Clone app ─────────────────────────────────────────────────────────────────
# echo "==> [6/7] Cloning app..."
# # Replace the URL below with your actual repo URL
# git clone https://github.com/SudhirVS/sample-app-v1.git "$APP_DIR"
# chown -R ubuntu:ubuntu "$APP_DIR"

# # ── Deploy ────────────────────────────────────────────────────────────────────
# echo "==> [7/7] Deploying app as ubuntu user..."
# sudo -u ubuntu bash -c "
#   export HOME=/home/ubuntu
#   export LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS}

#   # Start Minikube with docker driver
#   minikube start --driver=docker --cpus=3 --memory=12288 --disk-size=25g

#   # Point shell to Minikube's Docker daemon
#   eval \$(minikube docker-env)

#   # Build images
#   docker build -t user-service:latest ${APP_DIR}/services/user-service
#   docker build -t order-service:latest ${APP_DIR}/services/order-service

#   # SigNoz
#   helm repo add signoz https://charts.signoz.io
#   helm repo update
#   kubectl apply -f ${APP_DIR}/signoz/namespace.yaml
#   helm upgrade --install signoz signoz/signoz \
#     --namespace platform \
#     --set frontend.service.type=NodePort \
#     --wait --timeout=8m

#   # OTel Collector
#   kubectl apply -f ${APP_DIR}/signoz/otel-collector-rbac.yaml
#   kubectl apply -f ${APP_DIR}/signoz/otel-collector-configmap.yaml
#   sed 's/value: \"7\"/value: \"${LOG_RETENTION_DAYS}\"/' \
#     ${APP_DIR}/signoz/otel-collector-daemonset.yaml | kubectl apply -f -

#   # Microservices
#   helm dependency update ${APP_DIR}/helm/user-service
#   helm dependency update ${APP_DIR}/helm/order-service
#   helm upgrade --install user-service ${APP_DIR}/helm/user-service --namespace default --wait
#   helm upgrade --install order-service ${APP_DIR}/helm/order-service --namespace default --wait

#   # Print URLs
#   echo '--- Access URLs ---'
#   echo 'User Service:  '\$(minikube service user-service --url)
#   echo 'Order Service: '\$(minikube service order-service --url)
#   echo 'SigNoz UI:     '\$(minikube service signoz-frontend --namespace platform --url)
# " >> /var/log/user-data.log 2>&1

# echo "==> Bootstrap complete. Check /var/log/user-data.log for URLs."
