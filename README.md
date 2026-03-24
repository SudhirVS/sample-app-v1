# Sample Microservices App

Minimal two-service Node.js app deployed on Minikube with SigNoz centralized logging.

## Structure

```
sample-app-v1/
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

## Cluster Prerequisites

The following must be installed on the machine before deploying:

| Tool | Version | Install |
|---|---|---|
| Docker | 20.10+ | https://docs.docker.com/get-docker/ |
| Minikube | 1.30+ | https://minikube.sigs.k8s.io/docs/start/ |
| kubectl | 1.26+ | https://kubernetes.io/docs/tasks/tools/ |
| Helm | 3.12+ | https://helm.sh/docs/intro/install/ |

Minimum machine resources required:
- 4 vCPU
- 8 GB RAM (16 GB recommended for SigNoz ClickHouse)
- 30 GB free disk

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
4. Deploy OTel Collector DaemonSet to collect logs from all pods
5. Deploy user-service and order-service via Helm into `default` namespace
6. Print access URLs

## Access Services

After deploy, use port-forwarding to access from your browser:

```bash
kubectl port-forward svc/user-service 3000:3000 --address 0.0.0.0 &
kubectl port-forward svc/order-service 3001:3001 --address 0.0.0.0 &
kubectl port-forward svc/signoz 8080:8080 --address 0.0.0.0 -n platform &
```

Then open:
- User Service: `http://<host-ip>:3000/users`
- Order Service: `http://<host-ip>:3001/orders`
- SigNoz UI: `http://<host-ip>:8080`

## Logging Architecture

```
Pod stdout (JSON)
      │
      ▼
OTel Collector DaemonSet
      │  reads: /var/log/pods/*/*/*.log
      │  tags:  k8s.namespace.name, service.name, k8s.cluster.name
      │  drops: logs older than LOG_RETENTION_DAYS
      ▼
SigNoz OTel Collector (OTLP gRPC :4317)
      ▼
SigNoz ClickHouse (storage)
      ▼
SigNoz Frontend UI (Logs Explorer)
```

Each pod emits structured JSON logs with `service` and `namespace` fields. The OTel Collector additionally tags every log record with:

| Resource Attribute | Source |
|---|---|
| `k8s.namespace.name` | Extracted from pod log file path |
| `service.name` | Extracted from container name in log file path |
| `k8s.cluster.name` | Hardcoded as `minikube` |

## Viewing Logs in SigNoz

1. Open SigNoz UI at `http://<host-ip>:8080`
2. Click **Logs** → **Logs Explorer** in the left sidebar
3. Set time range to **Last 15 minutes**
4. Filter logs using:

| Filter | Key | Example Value |
|---|---|---|
| By namespace | `k8s.namespace.name` | `default` |
| By service | `service.name` | `user-service` |
| By message | `body` | `GET /users called` |

## Log Retention

Default retention is **15 days**. Log retention is controlled at two levels:

### 1. OTel Collector (pipeline-level)
The `filter/retention` processor drops log records older than `LOG_RETENTION_DAYS` before they reach SigNoz. Set via env variable:

```bash
LOG_RETENTION_DAYS=30 bash deploy.sh
```

### 2. SigNoz ClickHouse (storage-level)
The `queryService.retentionPeriod` Helm value controls how long SigNoz stores logs in ClickHouse. This is automatically set by `deploy.sh` using `LOG_RETENTION_DAYS`. To update independently:

```bash
helm upgrade signoz signoz/signoz \
  --namespace platform \
  --reuse-values \
  --set queryService.retentionPeriod=30
```

## Onboarding a New Microservice

Follow these steps to add a new service (e.g. `payment-service`):

### 1. Create the service

```
services/
└── payment-service/
    ├── Dockerfile
    ├── index.js
    └── package.json
```

Emit structured JSON logs to stdout:

```js
const log = (msg) =>
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: process.env.SERVICE_NAME,
    namespace: process.env.NAMESPACE,
    message: msg
  }));
```

### 2. Create a Helm chart

```bash
mkdir -p helm/payment-service/templates
```

`helm/payment-service/Chart.yaml`:
```yaml
apiVersion: v2
name: payment-service
description: Helm chart for payment-service
type: application
version: 0.1.0
dependencies:
  - name: default-chart
    version: "0.1.0"
    repository: "file://../default-chart"
```

`helm/payment-service/templates/deployment.yaml`:
```yaml
{{ include "default-chart.deployment" . }}
```

`helm/payment-service/templates/service.yaml`:
```yaml
{{ include "default-chart.service" . }}
```

`helm/payment-service/values.yaml`:
```yaml
replicaCount: 1

image:
  repository: payment-service
  tag: "latest"
  pullPolicy: Never

service:
  type: NodePort
  port: 3002

env:
  - name: PORT
    value: "3002"

livenessProbe:
  path: /health
  initialDelaySeconds: 10
  periodSeconds: 15

readinessProbe:
  path: /health
  initialDelaySeconds: 5
  periodSeconds: 10
```

### 3. Add to deploy.sh

```bash
# Build image
docker build -t payment-service:latest ./services/payment-service

# Deploy via Helm
helm dependency update helm/payment-service
helm upgrade --install payment-service helm/payment-service --namespace default --wait
```

### 4. Logs appear automatically

No changes needed to the OTel Collector. It collects logs from **all pods** across all namespaces. Logs from `payment-service` will appear in SigNoz filtered by:
- `k8s.namespace.name = default`
- `service.name = payment-service`

## Helm Override Examples

```bash
# Scale up user-service
helm upgrade user-service helm/user-service --set replicaCount=3

# Change log retention to 30 days
LOG_RETENTION_DAYS=30 bash deploy.sh
```
