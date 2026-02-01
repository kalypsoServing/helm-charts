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

### Option A: Colima + K3s (추천 - eBPF 지원)

ARM64 Mac에서 eBPF 프로파일링을 포함한 전체 스택 테스트에 적합합니다.
Colima는 Apple Virtualization.framework 기반의 실제 Linux VM을 제공하므로 eBPF tracepoint에 대한 커널 레벨 접근이 가능합니다.

```bash
git clone https://github.com/KalypsoServing/helm-charts
cd helm-charts

# 1. Colima + K3s 클러스터 생성
make cluster-colima

# 2. eBPF 지원 검증
make verify-ebpf

# 3. ArgoCD 설치 (Helm, kustomize.buildOptions 포함)
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade -i argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f argocd/values.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d


# 4. 배포
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applicationset.yaml

watch kubectl get pods -A
```

Prerequisites: `brew install colima kubectl helm` + `helm repo add argo https://argoproj.github.io/argo-helm`

### Option B: Kind (레거시 - eBPF 미지원)

Kind는 nested container 환경(Host -> Docker -> Kind Node -> Pod)이므로 eBPF tracepoint 접근이 제한됩니다. eBPF 프로파일링이 필요 없는 경우에만 사용하세요.

```bash
git clone https://github.com/KalypsoServing/helm-charts
cd helm-charts

make cluster-kind

helm upgrade -i argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f argocd/values.yaml \
  --wait

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

### Access UIs

```bash
make port-forward-grafana   # Grafana  → http://localhost:3000
make port-forward-minio     # MinIO    → http://localhost:9001
make port-forward-argocd    # ArgoCD   → http://localhost:8080
```

Grafana credentials:
- User: `admin`
- Pass: `kubectl get secret -n grafana grafana -o jsonpath="{.data.admin-password}" | base64 -d`

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

### ApplicationSet Discovery

The ApplicationSet uses Git file generator with `manifests/*/namespace.yaml` to discover manifests. Each manifest directory must have a `namespace.yaml` with sync-wave annotation:

```yaml
# manifests/<component>/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-component
  labels:
    name: my-component
  annotations:
    argocd.argoproj.io/sync-wave: "4"
```

To add a new component, create `manifests/<name>/` with `kustomization.yaml`, `values.yaml`, and `namespace.yaml`. ArgoCD will automatically deploy it.

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
- Linux nodes with kernel 5.x+ (for eBPF profiling)

### ARM64 Mac (Apple Silicon)

| 방식 | eBPF 지원 | 설치 |
|------|----------|------|
| **Colima + K3s** (추천) | Full | `brew install colima kubectl helm` |
| Kind | 미지원 | `brew install kind kubectl helm` |

```bash
# Colima 방식 (추천)
brew install colima kubectl helm

# Kind 방식 (레거시)
brew install kind kubectl helm
```

Colima는 `--vm-type vz`로 Apple Virtualization.framework 기반 VM을 생성하여 실제 Linux 커널 6.x에서 eBPF를 실행합니다.

### Enable Kustomize Helm Support in ArgoCD

This is required for ArgoCD to render Helm charts via Kustomize:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"kustomize.buildOptions":"--enable-helm"}}'

# Restart ArgoCD components to pick up the change
kubectl delete pods -n argocd -l app.kubernetes.io/name=argocd-repo-server
kubectl delete pods -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
```

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

### Makefile Targets

```bash
make help                   # 사용 가능한 모든 타겟 표시
make cluster-colima         # Colima + K3s 클러스터 생성
make cluster-colima-delete  # Colima 클러스터 삭제
make cluster-kind           # Kind 클러스터 생성 (레거시)
make cluster-kind-delete    # Kind 클러스터 삭제
make deploy                 # ArgoCD 기반 전체 배포
make deploy-manual          # Kustomize 직접 배포 (ArgoCD 없이)
make verify                 # 전체 pod 상태 확인
make verify-ebpf            # eBPF 지원 검증
make port-forward-grafana   # Grafana 포트포워드 (:3000)
make port-forward-minio     # MinIO 콘솔 포트포워드 (:9001)
make port-forward-argocd    # ArgoCD UI 포트포워드 (:8080)
make lint                   # Kustomize 매니페스트 검증
```

### Validate Kustomization

```bash
make lint
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
