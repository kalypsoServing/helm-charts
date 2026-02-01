# Kalypso Infrastructure

Multi-namespace Kubernetes observability stack with **LGTM (Loki, Grafana, Tempo, Mimir) + Pyroscope + Istio + MinIO**, deployed via Kustomize + ArgoCD ApplicationSet.

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

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applicationset.yaml

watch kubectl get pods -A
```

ArgoCD will automatically deploy in order:
1. **kalypso-otel** → OpenTelemetry Operator + eBPF instrumentation
2. **kalypso-istio** → Istio service mesh
3. **kalypso-minio** → S3-compatible storage
4. **kalypso-mimir/tempo/loki** → Metrics, traces, logs (parallel)
5. **kalypso-pyroscope** → Continuous profiling
6. **kalypso-grafana** → Dashboards

### Access Grafana

```bash
kubectl port-forward -n grafana svc/grafana 3000:80
# URL: http://localhost:3000
# User: admin
# Pass: kubectl get secret -n grafana grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

## Architecture

| Component | Namespace | Description |
|-----------|-----------|-------------|
| kalypso-otel | otel-system | OpenTelemetry Operator + eBPF |
| kalypso-istio | istio-system | Istio base + istiod |
| kalypso-minio | minio | MinIO standalone |
| kalypso-mimir | mimir | Mimir distributed (metrics) |
| kalypso-tempo | tempo | Tempo distributed (traces) |
| kalypso-loki | loki | Loki (logs) |
| kalypso-pyroscope | pyroscope | Pyroscope profiling |
| kalypso-grafana | grafana | Grafana dashboards |

### ArgoCD Sync Waves

```
Wave 1: kalypso-otel
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
- Mimir gateway: `mimir-gateway.mimir.svc.cluster.local:80`
- Tempo gateway: `tempo-gateway.tempo.svc.cluster.local:3100`
- Loki gateway: `loki-gateway.loki.svc.cluster.local:80`
- Pyroscope: `pyroscope.pyroscope.svc.cluster.local:4040`

## Helm Chart Versions

| Chart | Version | Repository |
|-------|---------|------------|
| opentelemetry-operator | 0.102.0 | https://open-telemetry.github.io/opentelemetry-helm-charts |
| opentelemetry-ebpf-instrumentation | 0.4.3 | https://open-telemetry.github.io/opentelemetry-helm-charts |
| istio (base) | 1.28.3 | https://istio-release.storage.googleapis.com/charts |
| istio (istiod) | 1.28.3 | https://istio-release.storage.googleapis.com/charts |
| minio | 5.4.0 | https://charts.min.io/ |
| mimir-distributed | 6.1.0-weekly.373 | https://grafana.github.io/helm-charts |
| tempo-distributed | 1.60.0 | https://grafana.github.io/helm-charts |
| loki | 6.49.0 | https://grafana.github.io/helm-charts |
| grafana | 10.5.12 | https://grafana.github.io/helm-charts |
| pyroscope | 1.18.0 | https://grafana.github.io/helm-charts |

## Prerequisites

- Kubernetes cluster (1.25+)
- ArgoCD installed with Kustomize Helm support enabled
- Linux nodes with kernel 4.9+ (for eBPF profiling)

## Installation

### Option 1: ArgoCD ApplicationSet (Recommended)

1. **Update Repository URL**

   Edit `argocd/applicationset.yaml`:
   ```yaml
   repoURL: https://github.com/YOUR_ORG/helm-charts.git
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

### Option 2: Manual Kustomize Installation

Install components in dependency order:

```bash
kubectl kustomize manifests/otel --enable-helm | kubectl apply -f -
kubectl kustomize manifests/istio --enable-helm | kubectl apply -f -
kubectl kustomize manifests/minio --enable-helm | kubectl apply -f -
kubectl kustomize manifests/mimir --enable-helm | kubectl apply -f -
kubectl kustomize manifests/tempo --enable-helm | kubectl apply -f -
kubectl kustomize manifests/loki --enable-helm | kubectl apply -f -
kubectl kustomize manifests/pyroscope --enable-helm | kubectl apply -f -
kubectl kustomize manifests/grafana --enable-helm | kubectl apply -f -
```

## Configuration

All configuration is managed through Kustomize `kustomization.yaml` files using `helmCharts` with `valuesFile`. Each manifest directory contains its own `values.yaml` (or chart-specific files like `values-operator.yaml` for multi-chart manifests).

### Example: Modify MinIO Credentials

Edit `manifests/minio/values.yaml`:

```yaml
rootUser: "newuser"
rootPassword: "newpassword"
```

Then update all dependent components (mimir, tempo, loki, pyroscope) in their respective `values.yaml` files with the new credentials.

### Example: Change Component Replicas

Edit `manifests/mimir/values.yaml`:

```yaml
ingester:
  replicas: 3
```

## Verification

```bash
kubectl get pods -A | grep -E "(otel|istio|minio|mimir|tempo|loki|pyroscope|grafana)"

kubectl get applications -n argocd

kubectl port-forward -n minio svc/kalypso-minio 9001:9001

kubectl port-forward -n grafana svc/grafana 3000:80
```

## Troubleshooting

### Kustomize Helm enablement

ArgoCD requires Kustomize Helm support. Verify ApplicationSet has:

```yaml
source:
  kustomize:
    enableHelm: true
```

### Cross-Namespace Service Resolution

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kalypso-minio.minio.svc.cluster.local

kubectl get networkpolicies -A
```

### View Rendered Manifests

```bash
kubectl kustomize manifests/otel --enable-helm
```

## Development

### Validate Kustomization

```bash
for manifest in manifests/*; do
  echo "Validating $manifest..."
  kubectl kustomize $manifest --enable-helm > /dev/null && echo "OK" || echo "FAILED"
done
```

### Test Single Component

```bash
kubectl kustomize manifests/minio --enable-helm | kubectl apply --dry-run=client -f -
```

## Architecture Decisions

- **Kustomize + Helm**: Uses Kustomize `helmCharts` field to manage Helm charts declaratively
- **No Kafka**: Mimir uses direct ingestion instead of Kafka buffering
- **No Alloy**: Pyroscope uses OTel eBPF profiler instead of Grafana Alloy
- **Standalone MinIO**: Single MinIO instance shared across all components (not production-ready)
- **Development Settings**: All components use replicas: 1 and minimal resource requests

## Migration from Helm Charts

This repository was migrated from pure Helm charts to Kustomize + Helm. The old `charts/` directory structure is deprecated. All configuration is now managed through `manifests/` with Kustomize.

## License

MIT
