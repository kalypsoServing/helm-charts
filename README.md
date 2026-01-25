# Kalypso Infrastructure Helm Charts

Multi-namespace Kubernetes observability stack with LGTM (Loki, Grafana, Tempo, Mimir) + Pyroscope + Istio + MinIO, deployed via ArgoCD ApplicationSet.

## Architecture

This repository contains 8 independent Helm charts, each deployed to its own namespace:

| Chart | Namespace | Components | Purpose |
|-------|-----------|------------|---------|
| kalypso-otel | otel-system | cert-manager, OpenTelemetry Operator | Certificate management and OTel infrastructure |
| kalypso-istio | istio-system | Istio base, istiod, gateway | Service mesh |
| kalypso-minio | minio | MinIO standalone | S3-compatible object storage |
| kalypso-mimir | mimir | Mimir distributed | Metrics storage (Prometheus-compatible) |
| kalypso-tempo | tempo | Tempo distributed | Distributed tracing |
| kalypso-loki | loki | Loki | Log aggregation |
| kalypso-pyroscope | pyroscope | Pyroscope + OTel eBPF Profiler | Continuous profiling |
| kalypso-grafana | grafana | Grafana | Dashboards and visualization |

### Deployment Order (ArgoCD Sync Waves)

```
Wave 1: otel (cert-manager must install first)
   ↓
Wave 2: istio
   ↓
Wave 3: minio
   ↓
Wave 4: mimir, tempo, loki (parallel)
   ↓
Wave 5: pyroscope
   ↓
Wave 6: grafana
```

### Cross-Namespace Communication

All components communicate via Kubernetes DNS FQDN:
- MinIO endpoint: `minio.minio.svc.cluster.local:9000`
- Mimir: `mimir-distributed-gateway.mimir.svc.cluster.local:80`
- Tempo: `tempo-distributed-query-frontend.tempo.svc.cluster.local:3100`
- Loki: `loki-gateway.loki.svc.cluster.local:80`
- Pyroscope: `pyroscope.pyroscope.svc.cluster.local:4040`

## Prerequisites

- Kubernetes cluster (1.25+)
- ArgoCD installed in the cluster
- Linux nodes with kernel 4.9+ (for eBPF profiling)
- Helm 3.x (for manual installation)

## Installation

### Option 1: ArgoCD ApplicationSet (Recommended)

1. **Build eBPF Profiler Image**

   ```bash
   cd docker/ebpf-profiler
   docker build -t ebpf-profiler:latest .
   
   # Push to your registry
   docker tag ebpf-profiler:latest your-registry/ebpf-profiler:latest
   docker push your-registry/ebpf-profiler:latest
   ```

   **ARM64 Support**: Edit `Dockerfile` line 17-18 to use `go1.22.10.linux-arm64.tar.gz`

2. **Update Repository URL**

   Edit `argocd/applicationset.yaml` line 52:
   ```yaml
   repoURL: https://github.com/YOUR_ORG/kalypso-infra-helm-chart.git
   ```

3. **Update eBPF Profiler Image**

   Edit `charts/kalypso-pyroscope/values.yaml`:
   ```yaml
   ebpfProfiler:
     image: your-registry/ebpf-profiler:latest
   ```

4. **Deploy via ArgoCD**

   ```bash
   kubectl apply -f argocd/project.yaml
   kubectl apply -f argocd/applicationset.yaml
   ```

5. **Monitor Deployment**

   ```bash
   kubectl get applications -n argocd
   argocd app list
   argocd app sync kalypso-otel
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

### eBPF Profiler Issues on ARM64

The eBPF profiler may have compatibility issues on ARM64. If you encounter problems:

1. Check profiler logs:
   ```bash
   kubectl logs -n pyroscope -l app=otel-ebpf-profiler
   ```

2. Disable eBPF profiler:
   ```yaml
   # charts/kalypso-pyroscope/values.yaml
   ebpfProfiler:
     enabled: false
   ```

3. Use alternative profiling methods (application-level instrumentation)

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
