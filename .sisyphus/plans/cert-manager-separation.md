# Plan: cert-manager 분리 및 전체 스택 검증

## Context

### Original Request
- cert-manager를 별도 release로 분리 (kalypso- prefix 없이)
- 모든 LGTM charts values.yaml 검증
- ArgoCD ApplicationSet으로 전체 스택 배포 가능하도록 설정
- README.md QuickStart 업데이트

### Problem
현재 `kalypso-otel` chart에 cert-manager와 opentelemetry-operator가 함께 있어서:
- CRDs가 설치되기 전에 Certificate 리소스 생성 시도
- Helm 단일 release로는 순서 제어 불가
- ArgoCD sync wave로 해결 가능하지만 같은 release 내에서는 불가

### User Constraint
- cert-manager chart는 `kalypso-` prefix 없이 `cert-manager`로 명명

---

## Work Objectives

### Core Objective
cert-manager를 별도 chart로 분리하여 ArgoCD sync wave 순서 제어 가능하게 함

### Concrete Deliverables
1. `charts/cert-manager/` - 새 chart (kalypso- prefix 없음)
2. `charts/kalypso-otel/` - cert-manager 의존성 제거
3. `argocd/applicationset.yaml` - sync wave 업데이트
4. `README.md` - QuickStart 업데이트

### Definition of Done
- [ ] `helm install cert-manager charts/cert-manager` 성공
- [ ] `helm install kalypso-otel charts/kalypso-otel` 성공 (cert-manager 설치 후)
- [ ] 모든 LGTM charts 설치 성공
- [ ] ArgoCD ApplicationSet 적용 시 전체 스택 배포

---

## TODOs

- [ ] 1. Create cert-manager chart (NO kalypso- prefix)

  **What to do**:
  - Create `charts/cert-manager/Chart.yaml`:
    ```yaml
    apiVersion: v2
    name: cert-manager
    description: cert-manager for Kalypso infrastructure
    type: application
    version: 0.1.0
    appVersion: "1.14.4"
    
    dependencies:
      - name: cert-manager
        version: "1.14.4"
        repository: "https://charts.jetstack.io"
    ```
  - Create `charts/cert-manager/values.yaml`:
    ```yaml
    cert-manager:
      installCRDs: true
    ```
  - Run `helm dependency build charts/cert-manager`

  **Parallelizable**: NO (must be first)

  **Acceptance Criteria**:
  - [ ] `helm lint charts/cert-manager` passes
  - [ ] `helm template test charts/cert-manager` renders without error

---

- [ ] 2. Update kalypso-otel to remove cert-manager

  **What to do**:
  - Edit `charts/kalypso-otel/Chart.yaml`:
    - Remove cert-manager dependency
    - Keep only opentelemetry-operator
  - Edit `charts/kalypso-otel/values.yaml`:
    - Remove cert-manager section
    - Keep opentelemetry-operator config
  - Delete old cert-manager subchart: `rm charts/kalypso-otel/charts/cert-manager-*.tgz`

  **References**:
  - `charts/kalypso-otel/Chart.yaml` - current dependencies
  - `charts/kalypso-otel/values.yaml` - current values

  **Parallelizable**: YES (with task 1)

  **Acceptance Criteria**:
  - [ ] `helm lint charts/kalypso-otel` passes
  - [ ] `helm template test charts/kalypso-otel` renders without error
  - [ ] No cert-manager dependency in Chart.yaml

---

- [ ] 3. Update ArgoCD ApplicationSet sync waves

  **What to do**:
  - Edit `argocd/applicationset.yaml`:
    - Add cert-manager as wave "0" (first)
    - Update otel to wave "1" (after cert-manager)
    - Keep other waves as is
  - Add cert-manager element:
    ```yaml
    - name: cert-manager
      namespace: cert-manager
      path: charts/cert-manager
      wave: "0"
    ```
  - Update repoURL to: `https://github.com/KalypsoServing/helm-charts.git`

  **References**:
  - `argocd/applicationset.yaml:10-41` - current elements list

  **Parallelizable**: YES (with tasks 1, 2)

  **Acceptance Criteria**:
  - [ ] ApplicationSet YAML is valid
  - [ ] cert-manager is wave "0", otel is wave "1"
  - [ ] repoURL points to KalypsoServing/helm-charts

---

- [ ] 4. Test full stack installation manually

  **What to do**:
  - Install in order on kind-kind cluster:
    1. `helm install cert-manager charts/cert-manager -n cert-manager --create-namespace`
    2. Wait for cert-manager pods ready
    3. `helm install kalypso-otel charts/kalypso-otel -n otel-system --create-namespace`
    4. `helm install kalypso-istio charts/kalypso-istio -n istio-system --create-namespace`
    5. `helm install kalypso-minio charts/kalypso-minio -n minio --create-namespace`
    6. `helm install kalypso-mimir charts/kalypso-mimir -n mimir --create-namespace`
    7. `helm install kalypso-tempo charts/kalypso-tempo -n tempo --create-namespace`
    8. `helm install kalypso-loki charts/kalypso-loki -n loki --create-namespace`
    9. `helm install kalypso-pyroscope charts/kalypso-pyroscope -n pyroscope --create-namespace`
    10. `helm install kalypso-grafana charts/kalypso-grafana -n grafana --create-namespace`

  **Parallelizable**: NO (sequential testing)

  **Acceptance Criteria**:
  - [ ] All helm install commands succeed
  - [ ] All pods reach Running state
  - [ ] No CRD ordering errors

---

- [ ] 5. Update README.md QuickStart

  **What to do**:
  - Update QuickStart section with:
    ```markdown
    ## QuickStart
    
    ```bash
    git clone https://github.com/KalypsoServing/helm-charts
    cd helm-charts
    
    # Install ArgoCD (if not already installed)
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    
    # Deploy full stack via ApplicationSet
    kubectl apply -f argocd/project.yaml
    kubectl apply -f argocd/applicationset.yaml
    ```
    ```

  **References**:
  - `README.md` - current content
  - `argocd/project.yaml` - ArgoCD project definition

  **Parallelizable**: YES (with task 4)

  **Acceptance Criteria**:
  - [ ] README.md has clear QuickStart section
  - [ ] Instructions are copy-paste ready

---

## Sync Wave Order (Final)

| Wave | Chart | Namespace | Reason |
|------|-------|-----------|--------|
| 0 | cert-manager | cert-manager | CRDs must exist first |
| 1 | kalypso-otel | otel-system | Needs cert-manager CRDs |
| 2 | kalypso-istio | istio-system | Independent |
| 3 | kalypso-minio | minio | Storage for LGTM |
| 4 | kalypso-mimir | mimir | Needs MinIO |
| 4 | kalypso-tempo | tempo | Needs MinIO |
| 4 | kalypso-loki | loki | Needs MinIO |
| 5 | kalypso-pyroscope | pyroscope | Needs MinIO |
| 6 | kalypso-grafana | grafana | Needs all datasources |

---

## Verification Commands

```bash
# Check all pods
kubectl get pods -A | grep -E "(cert-manager|otel|istio|minio|mimir|tempo|loki|pyroscope|grafana)"

# Check ArgoCD applications
kubectl get applications -n argocd

# Access Grafana
kubectl port-forward -n grafana svc/kalypso-grafana 3000:80
```
