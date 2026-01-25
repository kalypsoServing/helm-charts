# Kalypso Infrastructure Helm Charts

Multi-namespace Kubernetes observability stack with **LGTM (Loki, Grafana, Tempo, Mimir) + Pyroscope + Istio + MinIO**, deployed via ArgoCD ApplicationSet.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Grafana (grafana)                              │
│                    Dashboards + Explore + Alerting                          │
│         ┌──────────┬──────────┬──────────┬──────────────────┐               │
│         │  Mimir   │  Tempo   │   Loki   │    Pyroscope     │               │
│         │ metrics  │  traces  │   logs   │    profiles      │               │
└─────────┴────┬─────┴────┬─────┴────┬─────┴────────┬─────────┘               │
               │          │          │              │                          
     ┌─────────┴──────────┴──────────┴──────────────┴─────────┐               
     │                    MinIO (minio)                        │               
     │              S3-compatible Object Storage               │               
     │   [mimir-data] [tempo-traces] [loki-chunks] [pyroscope] │               
     └─────────────────────────────────────────────────────────┘               
               │                              │                                
     ┌─────────┴──────────┐         ┌─────────┴──────────┐                    
     │  Istio (istio)     │         │  OTel (otel)       │                    
     │  Service Mesh      │         │  Operator + Certs  │                    
     └────────────────────┘         └────────────────────┘                    
```

## QuickStart

```bash
git clone https://github.com/KalypsoServing/helm-charts
cd helm-charts

kind create cluster --config ./kind-config.yaml

# Install ArgoCD (if not already installed)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Deploy entire stack
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applicationset.yaml

# Monitor deployment
watch kubectl get pods -A
```

ArgoCD will automatically deploy in order:
1. **cert-manager** → Certificate management
2. **kalypso-otel** → OpenTelemetry Operator  
3. **kalypso-istio** → Istio service mesh
4. **kalypso-minio** → S3-compatible storage
5. **kalypso-mimir/tempo/loki** → Metrics, traces, logs
6. **kalypso-pyroscope** → Continuous profiling
7. **kalypso-grafana** → Dashboards

### Access Grafana

```bash
kubectl port-forward -n grafana svc/kalypso-grafana 3000:80
# URL: http://localhost:3000
# User: admin
# Pass: kubectl get secret -n grafana kalypso-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

### Manual Installation (Alternative)

```bash
helm install cert-manager charts/cert-manager -n cert-manager --create-namespace --wait
helm install kalypso-otel charts/kalypso-otel -n otel-system --create-namespace
helm install kalypso-istio charts/kalypso-istio -n istio-system --create-namespace
helm install kalypso-minio charts/kalypso-minio -n minio --create-namespace
helm install kalypso-mimir charts/kalypso-mimir -n mimir --create-namespace
helm install kalypso-tempo charts/kalypso-tempo -n tempo --create-namespace
helm install kalypso-loki charts/kalypso-loki -n loki --create-namespace
helm install kalypso-pyroscope charts/kalypso-pyroscope -n pyroscope --create-namespace
helm install kalypso-grafana charts/kalypso-grafana -n grafana --create-namespace
```

## Architecture

| Chart | Namespace | Components |
|-------|-----------|------------|
| cert-manager | cert-manager | cert-manager (CRDs for certificates) |
| kalypso-otel | otel-system | OpenTelemetry Operator |
| kalypso-istio | istio-system | Istio base, istiod |
| kalypso-minio | minio | MinIO standalone |
| kalypso-mimir | mimir | Mimir distributed (metrics) |
| kalypso-tempo | tempo | Tempo distributed (traces) |
| kalypso-loki | loki | Loki (logs) |
| kalypso-pyroscope | pyroscope | Pyroscope + eBPF profiler |
| kalypso-grafana | grafana | Grafana dashboards |

### ArgoCD Sync Waves

```
Wave 0: cert-manager (CRDs must exist first)
   ↓
Wave 1: kalypso-otel (needs cert-manager)
   ↓
Wave 2: kalypso-istio
   ↓
Wave 3: kalypso-minio (storage for LGTM)
   ↓
Wave 4: kalypso-mimir, kalypso-tempo, kalypso-loki (parallel)
   ↓
Wave 5: kalypso-pyroscope
   ↓
Wave 6: kalypso-grafana
```

### Cross-Namespace Communication

All components communicate via Kubernetes DNS FQDN:
- MinIO endpoint: `kalypso-minio.minio.svc.cluster.local:9000`
- Mimir: `mimir-distributed-gateway.mimir.svc.cluster.local:80`
- Tempo: `tempo-distributed-query-frontend.tempo.svc.cluster.local:3100`
- Loki: `loki-gateway.loki.svc.cluster.local:80`
- Pyroscope: `pyroscope.pyroscope.svc.cluster.local:4040`

## Chart Versions

This repository uses the following Helm chart versions:

| Chart | Helm Chart Version | Repository | Notes |
|-------|-------------------|------------|-------|
| cert-manager | 1.19.2 | https://charts.jetstack.io | Certificate management |
| opentelemetry-operator | 0.102.0 | https://open-telemetry.github.io/opentelemetry-helm-charts | OTel Operator |
| istio (base) | 1.28.3 | https://istio-release.storage.googleapis.com/charts | Istio base |
| istio (istiod) | 1.28.3 | https://istio-release.storage.googleapis.com/charts | Istio control plane |
| minio | 5.4.0 | https://charts.min.io/ | S3-compatible storage |
| mimir-distributed | 6.1.0-weekly.373 | https://grafana.github.io/helm-charts | Metrics storage (weekly) |
| tempo-distributed | 1.60.0 | https://grafana.github.io/helm-charts | Distributed tracing |
| loki | 6.49.0 | https://grafana.github.io/helm-charts | Log aggregation |
| grafana | 10.5.12 | https://grafana.github.io/helm-charts | Dashboards & visualization |
| pyroscope | 1.18.0 | https://grafana.github.io/helm-charts | Continuous profiling |

> **Note**: mimir-distributed uses a weekly build. For production, consider using a stable release version.

## Prerequisites

- Kubernetes cluster (1.25+)
- ArgoCD installed in the cluster
- Linux nodes with kernel 4.9+ (for eBPF profiling)
- Helm 3.x (for manual installation)

## eBPF Profiler Setup

The Pyroscope chart includes an OTel eBPF profiler for automatic continuous profiling of all applications without code changes.

### Default Configuration (Linux AMD64)

The eBPF profiler is pre-configured for **Linux AMD64** nodes using the official OpenTelemetry image:

```yaml
ebpfProfiler:
  enabled: true
  image: "otel/opentelemetry-ebpf-profiler-dev:202501021410"
  nodeSelector:
    kubernetes.io/os: linux
    kubernetes.io/arch: amd64
```

No additional setup required for Linux AMD64 clusters.

### ARM64 Configuration

For ARM64 nodes (e.g., AWS Graviton, Apple Silicon), update `charts/kalypso-pyroscope/values.yaml`:

```yaml
ebpfProfiler:
  enabled: true
  image: "otel/opentelemetry-ebpf-profiler-dev:202501021410"
  nodeSelector:
    kubernetes.io/os: linux
    kubernetes.io/arch: arm64
```

### Disable eBPF Profiler

If you don't need eBPF profiling:

```yaml
ebpfProfiler:
  enabled: false
```

### Build Custom Image (Optional)

To build your own eBPF profiler image:

```bash
cd docker/ebpf-profiler
docker build -t your-registry/ebpf-profiler:latest .
docker push your-registry/ebpf-profiler:latest
```

Then update `charts/kalypso-pyroscope/values.yaml`:

```yaml
ebpfProfiler:
  image: "your-registry/ebpf-profiler:latest"
```

## Installation

### Option 1: ArgoCD ApplicationSet (Recommended)

1. **Update Repository URL**

   Edit `argocd/applicationset.yaml` line 52:
   ```yaml
   repoURL: https://github.com/YOUR_ORG/kalypso-infra-helm-chart.git
   ```

2. **Deploy via ArgoCD**

   ```bash
   kubectl apply -f argocd/project.yaml
   kubectl apply -f argocd/applicationset.yaml
   ```

3. **Monitor Deployment**

   ```bash
   kubectl get applications -n argocd
   watch kubectl get pods -A
   ```

### Option 2: Manual Helm Installation

Install charts in dependency order:

```bash
# Wave 1: OTel
helm dependency build charts/kalypso-otel
helm install kalypso-otel charts/kalypso-otel -n otel-system --create-namespace

# Wave 2: Istio
helm dependency build charts/kalypso-istio
helm install kalypso-istio charts/kalypso-istio -n istio-system --create-namespace

# Wave 3: MinIO
helm dependency build charts/kalypso-minio
helm install kalypso-minio charts/kalypso-minio -n minio --create-namespace

# Wave 4: LGTM Stack (parallel)
helm dependency build charts/kalypso-mimir
helm install kalypso-mimir charts/kalypso-mimir -n mimir --create-namespace

helm dependency build charts/kalypso-tempo
helm install kalypso-tempo charts/kalypso-tempo -n tempo --create-namespace

helm dependency build charts/kalypso-loki
helm install kalypso-loki charts/kalypso-loki -n loki --create-namespace

# Wave 5: Pyroscope
helm dependency build charts/kalypso-pyroscope
helm install kalypso-pyroscope charts/kalypso-pyroscope -n pyroscope --create-namespace

# Wave 6: Grafana
helm dependency build charts/kalypso-grafana
helm install kalypso-grafana charts/kalypso-grafana -n grafana --create-namespace
```

## Configuration

### MinIO Credentials

Default credentials (change in production):
```yaml
# charts/kalypso-minio/values.yaml
minio:
  rootUser: minioadmin
  rootPassword: minioadmin
```

### Grafana Access

```bash
# Get Grafana admin password
kubectl get secret -n grafana kalypso-grafana -o jsonpath="{.data.admin-password}" | base64 -d

# Port forward to access UI
kubectl port-forward -n grafana svc/kalypso-grafana 3000:80
```

Access Grafana at http://localhost:3000 (admin / <password>)

### Disabling Components

Each chart can be disabled via values:

```yaml
# charts/kalypso-otel/values.yaml
cert-manager:
  enabled: false

# charts/kalypso-istio/values.yaml
base:
  enabled: false
```

## Verification

```bash
# Check all pods are running
kubectl get pods -A | grep kalypso

# Check ArgoCD applications
kubectl get applications -n argocd

# Verify MinIO buckets
kubectl port-forward -n minio svc/kalypso-minio 9001:9001
# Access MinIO Console at http://localhost:9001

# Check Grafana datasources
kubectl port-forward -n grafana svc/kalypso-grafana 3000:80
# Navigate to Configuration > Data Sources
```

## Troubleshooting

### eBPF Profiler Not Scheduling

If eBPF profiler pods show `0/0` in DaemonSet:

1. Check node architecture matches nodeSelector:
   ```bash
   kubectl get nodes --show-labels | grep arch
   kubectl get ds -n pyroscope
   ```

2. For ARM64 clusters, update `charts/kalypso-pyroscope/values.yaml`:
   ```yaml
   ebpfProfiler:
     nodeSelector:
       kubernetes.io/arch: arm64
   ```

### eBPF Profiler Logs

```bash
kubectl logs -n pyroscope -l app.kubernetes.io/component=ebpf-profiler
```

### Cert-Manager CRDs Not Installing

If cert-manager CRDs fail to install:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.crds.yaml
```

### Cross-Namespace Service Resolution

If services cannot reach each other:

```bash
# Verify DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup minio.minio.svc.cluster.local

# Check network policies
kubectl get networkpolicies -A
```

## Development

### Linting All Charts

```bash
for chart in charts/kalypso-*; do
  echo "Linting $chart..."
  helm lint $chart
done
```

### Template Rendering

```bash
for chart in charts/kalypso-*; do
  echo "Templating $chart..."
  helm template test $chart > /dev/null
done
```

## Architecture Decisions

- **No Kafka**: Mimir uses direct ingestion instead of Kafka buffering (simpler for development)
- **No Alloy**: Pyroscope uses OTel eBPF profiler instead of Grafana Alloy
- **Standalone MinIO**: Single MinIO instance shared across all components (not production-ready)
- **Development Settings**: All components use replicas: 1 and minimal resource requests

## License

MIT
