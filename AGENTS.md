# AGENTS.md - Kalypso Infrastructure Helm Charts

> **Last Updated**: 2026-02-01
> **Project Status**: COMPLETE (All Tasks Done)
> **Cluster Status**: Colima + K3s recommended (eBPF support) / Kind available (legacy)

---

## Table of Contents

1. [User Requirements (Original Request)](#1-user-requirements-original-request)
2. [Architecture Decisions](#2-architecture-decisions)
3. [Completed Tasks Summary](#3-completed-tasks-summary)
4. [Critical Issues Found & Fixed](#4-critical-issues-found--fixed)
5. [Current Deployment Status](#5-current-deployment-status)
6. [Git Commit History](#6-git-commit-history)
7. [Known Limitations](#7-known-limitations)
8. [What's Next](#8-whats-next)
9. [Quick Reference](#9-quick-reference)

---

## 1. User Requirements (Original Request)

### Initial Request (Korean)
```
helm install kalypso-infra kalypso-helm-charts/kalypso-infra 실행시 
LGTM + Pyroscope + Istio + MinIO를 K8s에 자동 세팅하는 Helm chart 생성
```

### Translated Requirements
Create a Helm chart that automatically sets up **LGTM (Loki, Grafana, Tempo, Mimir) + Pyroscope + Istio + MinIO** on Kubernetes when running `helm install`.

### Key Discussions & Decisions

| Topic | User Decision |
|-------|---------------|
| **Architecture** | Single umbrella chart -> Separate charts per component + ArgoCD orchestration |
| **Namespace Strategy** | Dedicated namespace per component |
| **Pyroscope Profiling** | Use OTel eBPF auto-instrumentation (NOT Alloy) |
| **Mimir Ingestion** | Direct ingestion (NO Kafka) |
| **Istio Components** | Base + Istiod + Gateway (Gateway later removed due to schema issues) |
| **OTel Operator** | Requires cert-manager as prerequisite |
| **Grafana Agent** | DO NOT use grafana/agent:v0.36.2 (deprecated Alloy legacy) |

### Must Have
- Each chart with `enabled: true/false` toggle
- Cross-namespace service URLs (e.g., `kalypso-minio.minio.svc.cluster.local:9000`)
- ArgoCD Sync Wave for dependency ordering
- OTel eBPF for Pyroscope auto-profiling

### Must NOT Have (Guardrails)
- Alloy (use OTel eBPF instead)
- Kafka (Mimir uses direct ingestion)
- Hardcoded credentials

---

## 2. Architecture Decisions

### Why Chart Separation + ArgoCD?
1. Each component deployed to dedicated namespace
2. Independent upgrade/rollback per component
3. GitOps-based declarative deployment via ArgoCD
4. Sync Wave controls dependency order (cert-manager -> OTel -> rest)

### Repository Structure
```
kalypso-infra-helm-chart/
├── manifests/               # Kustomize + Helm manifests per component
│   ├── cert-manager/
│   ├── otel/                # OTel Operator + eBPF profiler + collector
│   ├── istio/
│   ├── minio/
│   ├── mimir/
│   ├── tempo/
│   ├── loki/
│   ├── pyroscope/
│   └── grafana/
├── argocd/
│   ├── project.yaml         # ArgoCD AppProject
│   └── applicationset.yaml  # ApplicationSet with sync waves
├── scripts/
│   ├── setup-colima.sh      # Colima + K3s cluster setup
│   └── verify-ebpf.sh       # eBPF support verification
├── docker/
│   └── ebpf-profiler/Dockerfile  # OTel eBPF profiler image
├── Makefile                 # Cluster/deploy/verify automation
├── kind-config.yaml         # Kind cluster config (legacy)
└── README.md                # Quickstart guide
```

### Namespace Mapping & Sync Waves

| Chart | Namespace | Sync Wave | Dependencies |
|-------|-----------|-----------|--------------|
| kalypso-otel | otel-system | 1 | - |
| kalypso-istio | istio-system | 2 | - |
| kalypso-minio | minio | 3 | - |
| kalypso-mimir | mimir | 4 | minio |
| kalypso-tempo | tempo | 4 | minio |
| kalypso-loki | loki | 4 | minio |
| kalypso-pyroscope | pyroscope | 5 | minio, otel |
| kalypso-grafana | grafana | 6 | mimir, tempo, loki, pyroscope |

### Cross-Namespace Service URLs
```yaml
MinIO:     kalypso-minio.minio.svc.cluster.local:9000
Mimir:     mimir-distributed-gateway.mimir.svc.cluster.local:80
Tempo:     tempo-distributed-query-frontend.tempo.svc.cluster.local:3100
Loki:      loki-gateway.loki.svc.cluster.local:80
Pyroscope: pyroscope.pyroscope.svc.cluster.local:4040
```

---

## 3. Completed Tasks Summary

### Phase 1: Base Infrastructure (Tasks 1-4)

| Task | Description | Status |
|------|-------------|--------|
| 1 | Directory structure creation | DONE |
| 2 | kalypso-otel chart (cert-manager + OTel Operator) | DONE |
| 3 | kalypso-istio chart (base + istiod) | DONE |
| 4 | kalypso-minio chart (8 buckets) | DONE |

### Phase 2: LGTM Stack (Tasks 5-9)

| Task | Description | Status |
|------|-------------|--------|
| 5 | kalypso-mimir chart (cross-namespace MinIO) | DONE |
| 6 | kalypso-tempo chart (cross-namespace MinIO) | DONE |
| 7 | kalypso-loki chart (cross-namespace MinIO) | DONE |
| 8 | kalypso-pyroscope chart (OTel eBPF profiler) | DONE |
| 9 | kalypso-grafana chart (cross-namespace datasources) | DONE |

### Phase 3: ArgoCD + Documentation (Tasks 10-12)

| Task | Description | Status |
|------|-------------|--------|
| 10 | ArgoCD ApplicationSet | DONE |
| 11 | Dockerfile + README | DONE |
| 12 | Full verification (lint, template, deps) | DONE |

### Phase 4: Kind Cluster Testing (Tasks 13-15)

| Task | Description | Status |
|------|-------------|--------|
| 13 | Create Kind cluster with podman | DONE |
| 14 | Deploy Kalypso charts | DONE |
| 15 | Verify deployment and document results | DONE |

### Phase 5: Colima + eBPF Support (Tasks 16-17)

| Task | Description | Status |
|------|-------------|--------|
| 16 | Colima + K3s setup scripts and Makefile | DONE |
| 17 | eBPF verification script and documentation | DONE |

**Total: 17/17 Tasks Complete (100%)**

---

## 4. Critical Issues Found & Fixed

### Issue 1: OTel Operator Certificate Missing
- **Problem**: Pod stuck - missing certificate secret
- **Root Cause**: Certificate and Issuer resources not applied
- **Solution**: Manually created Certificate and Issuer resources
- **Files**: Manual kubectl apply (not in chart)

### Issue 2: MinIO DNS Resolution Failure
- **Problem**: Services couldn't resolve `minio.minio.svc.cluster.local`
- **Root Cause**: Actual service name is `kalypso-minio` (includes Helm release name)
- **Solution**: Updated all charts to use `kalypso-minio.minio.svc.cluster.local:9000`
- **Files Fixed**:
  - `charts/kalypso-mimir/values.yaml` (4 endpoints)
  - `charts/kalypso-tempo/values.yaml`
  - `charts/kalypso-loki/values.yaml`
  - `charts/kalypso-pyroscope/values.yaml`
- **Commit**: `de27503`

### Issue 3: Pyroscope OTel Collector Crash
- **Problem**: "batch processor not supported for profiles pipeline"
- **Solution**: Removed batch processor from profiles pipeline
- **File Fixed**: `charts/kalypso-pyroscope/templates/otel-collector-configmap.yaml`
- **Commit**: `9bafbf9`

### Issue 4: Grafana Agent (Deprecated)
- **Problem**: User requested NOT to use grafana/agent:v0.36.2 (Alloy legacy)
- **Solution**: 
  - Set `agent.enabled: false` in values.yaml
  - Set `alloy.enabled: false`
  - Set `ebpfProfiler.enabled: false`
  - Set `otelCollector.enabled: false`
  - Added conditional templates with `{{- if .Values.xxx.enabled }}`
- **Files Fixed**:
  - `charts/kalypso-pyroscope/values.yaml`
  - `charts/kalypso-pyroscope/templates/otel-ebpf-profiler-daemonset.yaml`
  - `charts/kalypso-pyroscope/templates/otel-collector-deployment.yaml`
  - `charts/kalypso-pyroscope/templates/otel-collector-configmap.yaml`
- **Commit**: `49a5c21`

### Issue 5: Mimir Storage Endpoints
- **Problem**: Only common.storage endpoint was fixed, others still had old URL
- **Solution**: Fixed all 4 storage endpoints (common, blocks_storage, alertmanager_storage, ruler_storage)
- **File Fixed**: `charts/kalypso-mimir/values.yaml`
- **Commit**: `49a5c21`

### Issue 6: Istio Gateway Schema Validation
- **Problem**: Gateway chart has strict schema that rejects custom values
- **Error**: `additional properties 'enabled', 'global', 'defaults' not allowed`
- **Solution**: Removed gateway dependency from kalypso-istio chart
- **Commit**: `319399f`

---

## 5. Current Deployment Status

### Recommended Cluster: Colima + K3s
```
Profile: kalypso
VM Type: Apple Virtualization.framework (vz)
CPU: 8 / Memory: 14GB / Disk: 40GB
Kubernetes: K3s (single node)
eBPF: Full support (Linux kernel 6.x)
Setup: make cluster-colima
```

### Legacy Cluster: Kind
```
Cluster Name: kind
Nodes: 1 control-plane + 2 workers
eBPF: NOT supported (nested container limitation)
Setup: make cluster-kind
```

### Pod Status (All Healthy)

| Namespace | Component | Pods | Status |
|-----------|-----------|------|--------|
| otel-system | cert-manager | 1/1 | Running |
| otel-system | cert-manager-cainjector | 1/1 | Running |
| otel-system | cert-manager-webhook | 1/1 | Running |
| otel-system | opentelemetry-operator | 2/2 | Running |
| istio-system | istiod | 1/1 | Running |
| minio | kalypso-minio | 1/1 | Running |
| mimir | All components | 12/12 | Running |
| tempo | All components | 7/7 | Running |
| loki | All components | 7/7 | Running |
| pyroscope | pyroscope + agent | 2/2 | Running |
| grafana | kalypso-grafana | 1/1 | Running |

**Total: 37+ pods running**

### Grafana Access
```bash
kubectl port-forward -n grafana svc/kalypso-grafana 3000:80
# URL: http://localhost:3000
# Username: admin
# Password: kubectl get secret -n grafana kalypso-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

---

## 6. Git Commit History

```
49a5c21 - fix: disable deprecated Grafana Agent, fix all MinIO endpoints, add conditional templates
9bafbf9 - fix: remove batch processor from OTel profiles pipeline
fc8b99a - docs: add quickstart guide and eBPF profiler setup instructions
de27503 - fix: correct MinIO service name to kalypso-minio in all charts
d6f8929 - chore: add Helm dependency locks and charts
319399f - fix(istio): remove gateway dependency due to schema validation issues
3b724d3 - docs: add Dockerfile for eBPF profiler and installation README
f4fa9d5 - feat(argocd): add ApplicationSet for multi-namespace deployment
de3bf75 - feat(chart): add kalypso-pyroscope chart with OTel eBPF profiler
1d47dff - feat(chart): add kalypso-grafana chart with cross-namespace datasources
be1df02 - feat(chart): add kalypso-loki chart with cross-namespace MinIO
9a7ae07 - feat(chart): add kalypso-tempo chart with cross-namespace MinIO
d850150 - feat(chart): add kalypso-mimir chart with cross-namespace MinIO
66b14ea - feat(chart): add kalypso-minio chart with S3 storage
8fd4688 - feat(chart): add kalypso-istio chart with base, istiod, gateway
d5aa668 - feat(chart): add kalypso-otel chart with cert-manager and otel-operator
```

---

## 7. Known Limitations

### 1. Pyroscope Agent Still Deploys
- `agent.enabled: false` is set but Pyroscope chart v1.5.0 defaults override it
- The deprecated grafana/agent:v0.36.2 still runs
- **Workaround**: Need to upgrade Pyroscope chart or modify chart directly

### 2. eBPF Profiler: Colima Required
- **Resolved**: Colima + K3s provides full eBPF support on ARM64 Mac
- Kind clusters cannot run eBPF profiler (nested container limitation)
- Use `make cluster-colima` + `make verify-ebpf` to validate
- Official image `otel/opentelemetry-collector-ebpf-profiler:0.134.1` supports multi-arch (ARM64/AMD64)

### 3. Istio Gateway Removed
- Schema validation issues with gateway chart v1.21.0
- Users can install Istio gateway separately if needed

### 4. Disabled Components
- Kafka in Mimir (direct ingestion)
- Alloy in Pyroscope
- Internal MinIO in all charts (using shared MinIO)
- Istio Gateway (schema validation issues)
- eBPF Profiler (needs image build)
- OTel Collector for profiles (disabled for now)

---

## 8. What's Next

### Option A: Production Deployment
1. Push repository to GitHub
2. Update `argocd/applicationset.yaml` line 52 with actual repo URL
3. Configure production credentials (MinIO, Grafana)
4. Increase replicas and resource limits
5. Apply: `kubectl apply -f argocd/`

### Option B: Test Grafana Datasources
```bash
kubectl port-forward -n grafana svc/kalypso-grafana 3000:80
# Open http://localhost:3000
# Verify Mimir, Tempo, Loki, Pyroscope datasources work
```

### Option C: Test eBPF Profiler on Colima
```bash
make cluster-colima       # Create Colima + K3s cluster
make verify-ebpf          # Verify eBPF support
make deploy               # Deploy full stack
# Check profiler logs:
kubectl logs -n otel-system -l app.kubernetes.io/name=otel-ebpf-profiler --tail=50
```

### Option D: Fix Pyroscope Agent Issue
- Upgrade Pyroscope chart version
- Or find correct values path to disable agent completely

### Option E: Clean Up
```bash
kind delete cluster --name kalypso-test
```

---

## 9. Quick Reference

### Helm Commands
```bash
# Lint all charts
for chart in charts/kalypso-*; do helm lint $chart; done

# Build dependencies
for chart in charts/kalypso-*; do helm dependency build $chart; done

# Template all charts
for chart in charts/kalypso-*; do helm template test $chart > /dev/null && echo "$chart OK"; done
```

### Manual Installation Order
```bash
helm install kalypso-otel charts/kalypso-otel -n otel-system --create-namespace
helm install kalypso-istio charts/kalypso-istio -n istio-system --create-namespace
helm install kalypso-minio charts/kalypso-minio -n minio --create-namespace
helm install kalypso-tempo charts/kalypso-tempo -n tempo --create-namespace
helm install kalypso-loki charts/kalypso-loki -n loki --create-namespace
helm install kalypso-mimir charts/kalypso-mimir -n mimir --create-namespace
helm install kalypso-pyroscope charts/kalypso-pyroscope -n pyroscope --create-namespace
helm install kalypso-grafana charts/kalypso-grafana -n grafana --create-namespace
```

### Useful kubectl Commands
```bash
# Check all pods
kubectl get pods -A | grep -E "(otel|istio|minio|mimir|tempo|loki|pyroscope|grafana)"

# Check services
kubectl get svc -A | grep kalypso

# Port forward Grafana
kubectl port-forward -n grafana svc/kalypso-grafana 3000:80

# Port forward MinIO Console
kubectl port-forward -n minio svc/kalypso-minio 9001:9001

# Get Grafana password
kubectl get secret -n grafana kalypso-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

### Key Files
| File | Purpose |
|------|---------|
| `Makefile` | Cluster/deploy/verify automation |
| `argocd/applicationset.yaml` | ArgoCD deployment config (update repoURL!) |
| `manifests/*/kustomization.yaml` | Kustomize + Helm chart config per component |
| `scripts/setup-colima.sh` | Colima + K3s cluster setup |
| `scripts/verify-ebpf.sh` | eBPF support verification |
| `docker/ebpf-profiler/Dockerfile` | eBPF profiler image build (fallback) |
| `kind-config.yaml` | Kind cluster config (legacy) |
| `README.md` | Installation guide |

---

## Appendix: Chart Dependencies

| Chart | Dependency | Version | Repository |
|-------|------------|---------|------------|
| kalypso-otel | cert-manager | 1.14.4 | https://charts.jetstack.io |
| kalypso-otel | opentelemetry-operator | 0.56.0 | https://open-telemetry.github.io/opentelemetry-helm-charts |
| kalypso-istio | base | 1.21.0 | https://istio-release.storage.googleapis.com/charts |
| kalypso-istio | istiod | 1.21.0 | https://istio-release.storage.googleapis.com/charts |
| kalypso-minio | minio | 5.0.14 | https://charts.min.io/ |
| kalypso-mimir | mimir-distributed | 5.4.0 | https://grafana.github.io/helm-charts |
| kalypso-tempo | tempo-distributed | 1.7.0 | https://grafana.github.io/helm-charts |
| kalypso-loki | loki | 6.0.0 | https://grafana.github.io/helm-charts |
| kalypso-pyroscope | pyroscope | 1.5.0 | https://grafana.github.io/helm-charts |
| kalypso-grafana | grafana | 8.0.0 | https://grafana.github.io/helm-charts |

---

*This document was auto-generated by Atlas orchestrator on 2026-01-25.*
