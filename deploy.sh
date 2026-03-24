#!/bin/bash
set -e

# Retention in days — override via: LOG_RETENTION_DAYS=30 bash deploy.sh
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-15}

echo "==> Starting Minikube..."
minikube start --driver=docker

echo "==> Pointing Docker to Minikube's daemon..."
eval $(minikube docker-env)

echo "==> Building Docker images inside Minikube..."
docker build -t user-service:latest ./services/user-service
docker build -t order-service:latest ./services/order-service

echo "==> Deploying SigNoz via Helm (log retention: ${LOG_RETENTION_DAYS} days)..."
helm repo add signoz https://charts.signoz.io
helm repo update
kubectl apply -f signoz/namespace.yaml
helm upgrade --install signoz signoz/signoz \
  --namespace platform \
  --values signoz/otel-collector-values.yaml \
  --set queryService.retentionPeriod=${LOG_RETENTION_DAYS} \
  --wait --timeout=10m

echo "==> Deploying microservices via Helm..."
helm dependency update helm/user-service
helm dependency update helm/order-service

helm upgrade --install user-service helm/user-service --namespace default --wait
helm upgrade --install order-service helm/order-service --namespace default --wait

echo ""
echo "==> All services deployed! (retention = ${LOG_RETENTION_DAYS} days)"
echo ""
echo "--- Port-forward to access services ---"
echo "kubectl port-forward svc/user-service 3000:3000 --address 0.0.0.0 &"
echo "kubectl port-forward svc/order-service 3001:3001 --address 0.0.0.0 &"
echo "kubectl port-forward svc/signoz 8080:8080 --address 0.0.0.0 -n platform &"
echo ""
echo "Then open:"
echo "  User Service:  http://<host-ip>:3000/users"
echo "  Order Service: http://<host-ip>:3001/orders"
echo "  SigNoz UI:     http://<host-ip>:8080"
