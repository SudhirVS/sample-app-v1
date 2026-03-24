# Sample Microservices App

Minimal two-service Node.js app deployed on Minikube with SigNoz centralized logging.

## Structure

```
sample-app/
├── services/
│   ├── user-service/        # GET /users, GET /health
│   └── order-service/       # GET /orders, GET /health
├── helm/
│   ├── default-chart/       # Library chart — shared defaults
│   ├── user-service/        # Overrides default-chart
│   └── order-service/       # Overrides default-chart
├── signoz/
│   ├── namespace.yaml
│   ├── otel-collector-rbac.yaml
│   ├── otel-collector-configmap.yaml
│   └── otel-collector-daemonset.yaml
└── deploy.sh
```

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm 3](https://helm.sh/docs/intro/install/)

## Deploy Everything

```bash
# Default log retention = 7 days
bash deploy.sh

# Custom log retention (e.g. 30 days)
LOG_RETENTION_DAYS=30 bash deploy.sh
```

The script will:
1. Start Minikube
2. Build Docker images inside Minikube's Docker daemon (no registry needed)
3. Deploy SigNoz via its official Helm chart into `platform` namespace
4. Deploy OTel Collector as a DaemonSet to collect logs from all pods
5. Deploy user-service and order-service via Helm into `default` namespace
6. Print access URLs

## Access Services

After deploy, the script prints URLs. You can also run:

```bash
minikube service user-service --url
minikube service order-service --url
minikube service signoz-frontend --namespace platform --url
```

## Helm Override Examples

Override any default value per microservice:

```bash
# Scale up user-service
helm upgrade user-service helm/user-service --set replicaCount=3

# Change log retention to 30 days (updates OTel DaemonSet env)
LOG_RETENTION_DAYS=30 bash deploy.sh
```

## Logging Architecture

```
Pod stdout (JSON)
      │
      ▼
OTel Collector DaemonSet (reads /var/log/pods/**)
      │  tags: k8s.namespace.name, service.name
      │  filters: drops logs older than LOG_RETENTION_DAYS
      ▼
SigNoz OTel Collector (OTLP gRPC :4317)
      ▼
SigNoz ClickHouse (storage)
      ▼
SigNoz Frontend UI (Logs Explorer)
```

All logs are structured JSON with `namespace` and `service` fields emitted by the app itself, and additionally tagged at the collector level via `k8s.namespace.name` and `service.name` resource attributes.

## Log Retention

Set `LOG_RETENTION_DAYS` env variable before running `deploy.sh`. The OTel Collector's filter operator drops log records older than N days before forwarding to SigNoz.

For storage-level retention in SigNoz ClickHouse, set via SigNoz Helm values:

```bash
helm upgrade signoz signoz/signoz \
  --namespace platform \
  --set clickhouse.coldStorage.enabled=false \
  --set queryService.retentionPeriod=<N>   # days
```
