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