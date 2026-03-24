#!/bin/bash
set -e

LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-7}

echo "==> Starting Minikube..."
minikube start --driver=docker

echo "==> Pointing Docker to Minikube's daemon..."
eval $(minikube docker-env)

echo "==> Building Docker images inside Minikube..."
docker build -t user-service:latest ./services/user-service
docker build -t order-service:latest ./services/order-service

echo "==> Deploying SigNoz via Helm..."
helm repo add signoz https://charts.signoz.io
helm repo update
kubectl apply -f signoz/namespace.yaml
helm upgrade --install signoz signoz/signoz \
  --namespace platform \
  --set signoz-frontend.service.type=NodePort \
  --wait --timeout=5m

echo "==> Deploying OpenTelemetry Collector (log retention: ${LOG_RETENTION_DAYS} days)..."
kubectl apply -f signoz/otel-collector-rbac.yaml
kubectl apply -f signoz/otel-collector-configmap.yaml

# Patch retention days into DaemonSet env before applying
sed "s/value: \"7\"/value: \"${LOG_RETENTION_DAYS}\"/" signoz/otel-collector-daemonset.yaml | kubectl apply -f -

echo "==> Deploying microservices via Helm..."
helm dependency update helm/user-service
helm dependency update helm/order-service

helm upgrade --install user-service helm/user-service --namespace default --wait
helm upgrade --install order-service helm/order-service --namespace default --wait

echo ""
echo "==> All services deployed!"
echo ""
echo "--- Access URLs ---"
echo "User Service:  $(minikube service user-service --url)"
echo "Order Service: $(minikube service order-service --url)"
echo "SigNoz UI:     $(minikube service signoz-signoz-frontend --namespace platform --url)"
