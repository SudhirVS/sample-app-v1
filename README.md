# Sample Microservices App

A two-service Node.js application deployed on Minikube with SigNoz centralized logging.

## Project Structure

```
sample-app-v1/
├── services/
│   ├── user-service/            # GET /users, GET /health  (port 3000)
│   └── order-service/           # GET /orders, GET /health (port 3001)
├── helm/
│   ├── default-chart/           # Shared library chart (base templates)
│   ├── user-service/            # Helm chart for user-service
│   └── order-service/           # Helm chart for order-service
├── signoz/
│   ├── namespace.yaml           # Creates 'platform' namespace
│   ├── otel-collector-values.yaml  # SigNoz Helm overrides for log collection
│   ├── otel-collector-rbac.yaml
│   ├── otel-collector-configmap.yaml
│   └── otel-collector-daemonset.yaml
└── deploy.sh                    # One-shot deploy script
```

---

## Cluster Prerequisites

### Required Tools

Install all tools below before running `deploy.sh`:

| Tool | Min Version | Install Guide |
|---|---|---|
| Docker | 20.10+ | https://docs.docker.com/get-docker/ |
| Minikube | 1.30+ | https://minikube.sigs.k8s.io/docs/start/ |
| kubectl | 1.26+ | https://kubernetes.io/docs/tasks/tools/ |
| Helm | 3.12+ | https://helm.sh/docs/intro/install/ |

Verify all tools are installed:

```bash
docker --version
minikube version
kubectl version --client
helm version
```

### Minimum Machine Resources

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 4 vCPU | 8 vCPU |
| RAM | 8 GB | 16 GB |
| Disk | 30 GB free | 50 GB free |

> SigNoz runs ClickHouse internally which is memory and disk intensive. 16 GB RAM is strongly recommended.

### EC2 Instance (if deploying on AWS)

- Instance type: `t3.xlarge` (minimum) or `t3.2xlarge` (recommended)
- AMI: Ubuntu 22.04 LTS
- Storage: 50 GB gp3

Security group inbound rules required:

| Port | Purpose |
|---|---|
| 22 | SSH |
| 3000 | user-service |
| 3001 | order-service |
| 8080 | SigNoz UI |

---

## Deploy Everything

```bash
# Default log retention = 15 days
bash deploy.sh

# Custom log retention
LOG_RETENTION_DAYS=30 bash deploy.sh
```

The script will:
1. Start Minikube with Docker driver
2. Build Docker images inside Minikube (no registry needed)
3. Deploy SigNoz via official Helm chart into `platform` namespace
4. Configure SigNoz built-in OTel Collector to collect logs from all pods
5. Deploy `user-service` and `order-service` via Helm into `default` namespace

## Access Services

Use port-forwarding to access from your browser:

```bash
kubectl port-forward svc/user-service 3000:3000 --address 0.0.0.0 &
kubectl port-forward svc/order-service 3001:3001 --address 0.0.0.0 &
kubectl port-forward svc/signoz 8080:8080 --address 0.0.0.0 -n platform &
```

| Service | URL |
|---|---|
| user-service | `http://<host-ip>:3000/users` |
| order-service | `http://<host-ip>:3001/orders` |
| SigNoz UI | `http://<host-ip>:8080` |

---

## Logging Architecture

```
Pod stdout (structured JSON)
        │
        ▼
SigNoz OTel Collector (filelog receiver)
        │  reads  : /var/log/pods/*/*/*.log
        │  tags   : k8s.namespace.name, service.name, k8s.cluster.name
        ▼
SigNoz ClickHouse (storage — 15 day retention)
        ▼
SigNoz UI → Logs Explorer
```

Every pod emits structured JSON to stdout:

```json
{
  "timestamp": "2026-03-24T18:00:00.000Z",
  "service": "user-service",
  "namespace": "default",
  "message": "GET /users called"
}
```

The OTel Collector tags each log record with these resource attributes:

| Attribute | Value | Source |
|---|---|---|
| `k8s.namespace.name` | `default` | Extracted from pod log file path |
| `service.name` | `user-service` | Extracted from container name in log file path |
| `k8s.cluster.name` | `minikube` | Hardcoded in collector config |

## Viewing Logs in SigNoz

1. Open `http://<host-ip>:8080`
2. Click **Logs** → **Logs Explorer** in the left sidebar
3. Set time range to **Last 15 minutes**
4. Click **Run Query**

Filter logs by:

| Filter | Key | Example Value |
|---|---|---|
| By namespace | `k8s.namespace.name` | `default` |
| By service | `service.name` | `user-service` |
| By message content | `body` | `GET /users called` |

---

## Log Retention

Default retention is **15 days**, controlled at the SigNoz ClickHouse storage level via the `queryService.retentionPeriod` Helm value. This is set automatically by `deploy.sh`.

To update retention independently without redeploying everything:

```bash
helm upgrade signoz signoz/signoz \
  --namespace platform \
  --reuse-values \
  --set queryService.retentionPeriod=15
```

---

## Onboarding a New Microservice

Follow these steps to add a new service, for example `payment-service`.

### Step 1 — Create the service

Create the service directory and files:

```
services/
└── payment-service/
    ├── Dockerfile
    ├── index.js
    └── package.json
```

`services/payment-service/package.json`:
```json
{
  "name": "payment-service",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": { "start": "node index.js" },
  "dependencies": { "express": "^4.18.2" }
}
```

`services/payment-service/index.js`:
```js
const express = require("express");
const app = express();
const PORT = process.env.PORT || 3002;
const SERVICE = process.env.SERVICE_NAME || "payment-service";
const NAMESPACE = process.env.NAMESPACE || "default";

const log = (msg) =>
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    service: SERVICE,
    namespace: NAMESPACE,
    message: msg
  }));

app.get("/health", (_, res) => res.json({ status: "ok" }));
app.get("/payments", (_, res) => {
  log("GET /payments called");
  res.json([{ id: 201, amount: 100, userId: 1 }]);
});

app.listen(PORT, () => log(`${SERVICE} running on port ${PORT}`));
```

`services/payment-service/Dockerfile`:
```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY index.js .
CMD ["node", "index.js"]
```

### Step 2 — Create the Helm chart

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

### Step 3 — Add to deploy.sh

Add these lines to `deploy.sh` after the existing service deployments:

```bash
# Build image inside Minikube
docker build -t payment-service:latest ./services/payment-service

# Deploy via Helm
helm dependency update helm/payment-service
helm upgrade --install payment-service helm/payment-service --namespace default --wait
```

### Step 4 — Access the new service

```bash
kubectl port-forward svc/payment-service 3002:3002 --address 0.0.0.0 &
```

Open: `http://<host-ip>:3002/payments`

### Step 5 — Logs appear automatically

No changes needed to SigNoz or the OTel Collector. It collects logs from **all pods across all namespaces** automatically.

In SigNoz UI → Logs Explorer, filter by:
- `k8s.namespace.name = default`
- `service.name = payment-service`

---

## Helm Override Examples

```bash
# Scale up user-service to 3 replicas
helm upgrade user-service helm/user-service --set replicaCount=3

# Change log retention to 30 days
LOG_RETENTION_DAYS=30 bash deploy.sh
```
