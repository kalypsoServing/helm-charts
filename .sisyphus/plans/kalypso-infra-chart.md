# kalypso-infra Helm Charts (Multi-Namespace + ArgoCD)

## Context

### Original Request
`helm install kalypso-infra kalypso-helm-charts/kalypso-infra` 실행시 LGTM + Pyroscope + Istio + MinIO를 K8s에 자동 세팅하는 Helm chart 생성

### Interview Summary (Updated)
**Key Discussions**:
- **아키텍처 변경**: 단일 umbrella chart → 컴포넌트별 분리 Chart + ArgoCD 오케스트레이션
- **Namespace 전략**: 각 컴포넌트별 dedicated namespace
- 컴포넌트: MinIO, Grafana, Mimir, Tempo, Loki, Pyroscope, Istio, OTel
- Pyroscope: OTel eBPF auto-instrumentation 사용 (Alloy 제외)
- Mimir: Kafka 비활성화, direct ingestion 사용
- Istio: Base + Istiod + Gateway 전체 설치
- cert-manager: OTel Operator 사전 요구사항
- Chart 버전: 0.1.0

**Reference Files**:
- `values/minio-values.yaml` - MinIO standalone 설정
- `values/mimir-values.yaml` - Mimir distributed 설정
- `values/tempo-values.yaml` - Tempo distributed 설정
- `values/grafana-values.yaml` - Grafana datasources 설정
- `values/pyroscope-values.yaml` - Pyroscope microservices 설정
- `values/otel-operator-values.yaml` - OTel Operator 설정
- `values/otel-collector.yaml` - OTel Collector 파이프라인

### Architecture Decision
**Why Chart Separation + ArgoCD**:
1. 각 컴포넌트를 dedicated namespace에 배포 가능
2. 컴포넌트별 독립적 업그레이드/롤백
3. ArgoCD로 GitOps 기반 선언적 배포
4. Sync Wave로 의존성 순서 제어 (cert-manager → OTel → 나머지)

---

## Work Objectives

### Core Objective
컴포넌트별 Helm Chart 분리 및 ArgoCD ApplicationSet으로 multi-namespace 배포 오케스트레이션

### Concrete Deliverables

**Charts** (8개):
```
charts/
├── kalypso-minio/           # MinIO (S3 storage)
├── kalypso-grafana/         # Grafana (dashboards)
├── kalypso-mimir/           # Mimir (metrics)
├── kalypso-tempo/           # Tempo (traces)
├── kalypso-loki/            # Loki (logs)
├── kalypso-pyroscope/       # Pyroscope + OTel eBPF Profiler
├── kalypso-istio/           # Istio (base + istiod + gateway)
└── kalypso-otel/            # cert-manager + OTel Operator
```

**ArgoCD Configuration**:
```
argocd/
├── project.yaml             # ArgoCD Project 정의
├── applicationset.yaml      # ApplicationSet (모든 charts 배포)
└── apps/                    # (optional) 개별 Application 정의
    ├── minio.yaml
    ├── grafana.yaml
    └── ...
```

**Supporting Files**:
- `docker/ebpf-profiler/Dockerfile` - eBPF Profiler 이미지 빌드
- `README.md` - 설치 가이드

### Namespace Mapping

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

### Definition of Done
- [x] 모든 8개 Chart가 `helm lint` 통과
- [x] ArgoCD ApplicationSet이 유효한 YAML
- [x] `helm template` 각 Chart 렌더링 성공
- [x] 서비스 URL이 cross-namespace 참조로 올바르게 설정

### Must Have
- 각 Chart에 `enabled: true/false` 토글
- Cross-namespace 서비스 URL (예: `minio.minio.svc.cluster.local:9000`)
- ArgoCD Sync Wave로 의존성 순서 보장
- OTel eBPF로 Pyroscope 자동 프로파일링

### Must NOT Have (Guardrails)
- Alloy 포함하지 않음 (OTel eBPF 사용)
- Kafka 포함하지 않음 (Mimir direct ingestion)
- 하드코딩된 credentials

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: NO (신규 프로젝트)
- **User wants tests**: Manual verification
- **Framework**: helm lint, helm template, argocd app diff (optional)

### Manual QA

| Type | Verification Tool | Procedure |
|------|------------------|-----------|
| Chart Structure | helm lint | 각 Chart 문법/구조 검증 |
| Rendering | helm template | 각 Chart YAML 렌더링 검증 |
| ArgoCD Config | kubectl apply --dry-run | ApplicationSet 유효성 검증 |

---

## Task Flow

```
Phase 1: Base Infrastructure
Task 1 (디렉토리 구조)
    ↓
Task 2 (kalypso-otel) → Task 3 (kalypso-istio) → Task 4 (kalypso-minio)
         [cert-manager + otel-operator]    [base + istiod + gateway]

Phase 2: LGTM Stack (병렬 가능)
    ↓
Task 5 (kalypso-mimir) ←→ Task 6 (kalypso-tempo) ←→ Task 7 (kalypso-loki)
    ↓
Task 8 (kalypso-pyroscope) [+ OTel eBPF Profiler]
    ↓
Task 9 (kalypso-grafana) [datasources 연동]

Phase 3: ArgoCD + Documentation
    ↓
Task 10 (ArgoCD ApplicationSet)
    ↓
Task 11 (Dockerfile + README)
    ↓
Task 12 (전체 검증)
```

## Parallelization

| Group | Tasks | Reason |
|-------|-------|--------|
| A | 5, 6, 7 | LGTM 컴포넌트들 독립적 |
| B | 2, 3 | cert-manager와 Istio 독립적 |

| Task | Depends On | Reason |
|------|------------|--------|
| 4 | 1 | 디렉토리 필요 |
| 5, 6, 7 | 4 | MinIO URL 참조 필요 |
| 8 | 2, 4 | OTel Operator + MinIO 필요 |
| 9 | 5, 6, 7, 8 | 모든 datasource 필요 |
| 10 | 2-9 | 모든 Chart 필요 |
| 12 | 10, 11 | 모든 파일 생성 후 |

---

## TODOs

- [x] 1. 디렉토리 구조 생성

  **What to do**:
  ```bash
  mkdir -p charts/kalypso-{minio,grafana,mimir,tempo,loki,pyroscope,istio,otel}/templates
  mkdir -p argocd/apps
  mkdir -p docker/ebpf-profiler
  ```

  **Must NOT do**:
  - 기존 `values/` 디렉토리 수정하지 않음

  **Parallelizable**: NO (첫 번째 작업)

  **Acceptance Criteria**:
  - [x] `ls charts/` → 8개 Chart 디렉토리 존재
  - [x] `ls argocd/` → argocd 디렉토리 존재

  **Commit**: NO (다음 작업과 그룹)

---

- [x] 2. kalypso-otel Chart 생성

  **What to do**:
  - `charts/kalypso-otel/Chart.yaml` - cert-manager + opentelemetry-operator 의존성
  - `charts/kalypso-otel/values.yaml` - 기본 설정
  - `charts/kalypso-otel/templates/_helpers.tpl`

  **Chart.yaml Dependencies**:
  ```yaml
  dependencies:
    - name: cert-manager
      version: "1.14.4"
      repository: "https://charts.jetstack.io"
      condition: cert-manager.enabled
    - name: opentelemetry-operator
      version: "0.56.0"
      repository: "https://open-telemetry.github.io/opentelemetry-helm-charts"
      condition: opentelemetry-operator.enabled
  ```

  **Must NOT do**:
  - OTel Collector 포함하지 않음 (pyroscope chart에서 관리)

  **Parallelizable**: YES (with Task 3)

  **References**:
  - `values/otel-operator-values.yaml` - OTel Operator 설정 패턴
  - cert-manager: https://cert-manager.io/docs/installation/helm/

  **Acceptance Criteria**:
  - [x] `helm lint charts/kalypso-otel` → 0 errors
  - [x] cert-manager CRDs 설치 옵션 포함 (`installCRDs: true`)

  **Commit**: YES
  - Message: `feat(chart): add kalypso-otel chart with cert-manager and otel-operator`
  - Files: `charts/kalypso-otel/*`

---

- [x] 3. kalypso-istio Chart 생성

  **What to do**:
  - `charts/kalypso-istio/Chart.yaml` - istio base, istiod, gateway 의존성
  - `charts/kalypso-istio/values.yaml` - 개발 환경 최적화 설정

  **Chart.yaml Dependencies**:
  ```yaml
  dependencies:
    - name: base
      version: "1.21.0"
      repository: "https://istio-release.storage.googleapis.com/charts"
      condition: base.enabled
    - name: istiod
      version: "1.21.0"
      repository: "https://istio-release.storage.googleapis.com/charts"
      condition: istiod.enabled
    - name: gateway
      version: "1.21.0"
      repository: "https://istio-release.storage.googleapis.com/charts"
      condition: gateway.enabled
  ```

  **Parallelizable**: YES (with Task 2)

  **References**:
  - Istio Helm: https://istio.io/latest/docs/setup/install/helm/

  **Acceptance Criteria**:
  - [x] `helm lint charts/kalypso-istio` → 0 errors
  - [x] pilot replicas: 1 (개발 환경)

  **Commit**: YES
  - Message: `feat(chart): add kalypso-istio chart with base, istiod, gateway`
  - Files: `charts/kalypso-istio/*`

---

- [x] 4. kalypso-minio Chart 생성

  **What to do**:
  - `charts/kalypso-minio/Chart.yaml` - MinIO 의존성
  - `charts/kalypso-minio/values.yaml` - standalone 설정, buckets 정의

  **Chart.yaml Dependencies**:
  ```yaml
  dependencies:
    - name: minio
      version: "5.0.14"
      repository: "https://charts.min.io/"
      condition: minio.enabled
  ```

  **Buckets** (기존 설정 유지):
  - tempo-bucket, loki-bucket, mimir-bucket
  - mimir-blocks, mimir-alertmanager, mimir-ruler
  - pyroscope-data, pyroscope-admin

  **Parallelizable**: NO (Task 1 완료 후)

  **References**:
  - `values/minio-values.yaml` - 전체 설정 참고

  **Acceptance Criteria**:
  - [x] `helm lint charts/kalypso-minio` → 0 errors
  - [x] 8개 bucket 정의됨

  **Commit**: YES
  - Message: `feat(chart): add kalypso-minio chart with S3 storage`
  - Files: `charts/kalypso-minio/*`

---

- [x] 5. kalypso-mimir Chart 생성

  **What to do**:
  - `charts/kalypso-mimir/Chart.yaml` - mimir-distributed 의존성
  - `charts/kalypso-mimir/values.yaml` - S3 backend (cross-namespace MinIO)

  **Cross-Namespace MinIO URL**:
  ```yaml
  endpoint: minio.minio.svc.cluster.local:9000
  ```

  **Must NOT do**:
  - Kafka 활성화하지 않음
  - 내장 MinIO 활성화하지 않음

  **Parallelizable**: YES (with Task 6, 7)

  **References**:
  - `values/mimir-values.yaml` - 설정 참고 (Kafka 부분 제외)

  **Acceptance Criteria**:
  - [ ] `helm lint charts/kalypso-mimir` → 0 errors
  - [ ] `kafka.enabled: false` 설정됨
  - [ ] `minio.enabled: false` 설정됨
  - [ ] S3 endpoint가 cross-namespace URL

  **Commit**: YES
  - Message: `feat(chart): add kalypso-mimir chart with cross-namespace MinIO`
  - Files: `charts/kalypso-mimir/*`

---

- [x] 6. kalypso-tempo Chart 생성

  **What to do**:
  - `charts/kalypso-tempo/Chart.yaml` - tempo-distributed 의존성
  - `charts/kalypso-tempo/values.yaml` - S3 backend (cross-namespace MinIO)

  **Cross-Namespace MinIO URL**:
  ```yaml
  endpoint: minio.minio.svc.cluster.local:9000
  bucket: tempo-bucket
  ```

  **Parallelizable**: YES (with Task 5, 7)

  **References**:
  - `values/tempo-values.yaml` - 전체 설정 참고

  **Acceptance Criteria**:
  - [ ] `helm lint charts/kalypso-tempo` → 0 errors
  - [ ] S3 endpoint가 cross-namespace URL

  **Commit**: YES
  - Message: `feat(chart): add kalypso-tempo chart with cross-namespace MinIO`
  - Files: `charts/kalypso-tempo/*`

---

- [x] 7. kalypso-loki Chart 생성

  **What to do**:
  - `charts/kalypso-loki/Chart.yaml` - loki 의존성
  - `charts/kalypso-loki/values.yaml` - S3 backend (cross-namespace MinIO)

  **Cross-Namespace MinIO URL**:
  ```yaml
  endpoint: minio.minio.svc.cluster.local:9000
  bucketNames:
    chunks: loki-bucket
    ruler: loki-bucket
  ```

  **Parallelizable**: YES (with Task 5, 6)

  **References**:
  - `values/tempo-values.yaml:5-16` - S3 storage 설정 패턴
  - Loki S3 config: https://grafana.com/docs/loki/latest/configure/storage/

  **Acceptance Criteria**:
  - [ ] `helm lint charts/kalypso-loki` → 0 errors
  - [ ] S3 endpoint가 cross-namespace URL

  **Commit**: YES
  - Message: `feat(chart): add kalypso-loki chart with cross-namespace MinIO`
  - Files: `charts/kalypso-loki/*`

---

- [x] 8. kalypso-pyroscope Chart 생성

  **What to do**:
  - `charts/kalypso-pyroscope/Chart.yaml` - pyroscope 의존성
  - `charts/kalypso-pyroscope/values.yaml` - S3 backend, Alloy 비활성화
  - `charts/kalypso-pyroscope/templates/otel-collector-configmap.yaml`
  - `charts/kalypso-pyroscope/templates/otel-collector-deployment.yaml`
  - `charts/kalypso-pyroscope/templates/otel-ebpf-profiler-daemonset.yaml`

  **OTel eBPF Profiler DaemonSet**:
  ```yaml
  spec:
    template:
      spec:
        hostPID: true
        containers:
          - name: profiler
            image: {{ .Values.ebpfProfiler.image }}
            command: ["/usr/local/bin/ebpf-profiler", 
                      "-collection-agent", "otel-collector:4317",
                      "-no-kernel-version-check", "-disable-tls", "-v"]
            securityContext:
              privileged: true
            volumeMounts:
              - name: kernel-debug
                mountPath: /sys/kernel/debug
              - name: proc
                mountPath: /proc
              - name: cgroup
                mountPath: /sys/fs/cgroup
  ```

  **OTel Collector profiles pipeline**:
  ```yaml
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
  exporters:
    otlp:
      endpoint: pyroscope:4040
      tls:
        insecure: true
  service:
    pipelines:
      profiles:
        receivers: [otlp]
        exporters: [otlp]
  ```

  **Must NOT do**:
  - Alloy 활성화하지 않음

  **Parallelizable**: NO (Task 4 완료 후)

  **References**:
  - `values/pyroscope-values.yaml` - 설정 참고 (alloy 부분 제외)
  - https://grafana.com/docs/pyroscope/latest/configure-client/opentelemetry/ebpf-profiler/
  - https://github.com/grafana/pyroscope/tree/main/examples/grafana-alloy-auto-instrumentation/ebpf-otel

  **버전 고정**:
  - OTel Collector: `otel/opentelemetry-collector-contrib:0.129.1`
  - Feature gate: `--feature-gates=service.profilesSupport`

  **Acceptance Criteria**:
  - [ ] `helm lint charts/kalypso-pyroscope` → 0 errors
  - [ ] `alloy.enabled: false` 설정됨
  - [ ] OTel Collector Deployment 포함
  - [ ] eBPF Profiler DaemonSet 포함
  - [ ] DaemonSet에 `hostPID: true`, `privileged: true`

  **Commit**: YES
  - Message: `feat(chart): add kalypso-pyroscope chart with OTel eBPF profiler`
  - Files: `charts/kalypso-pyroscope/*`

---

- [x] 9. kalypso-grafana Chart 생성

  **What to do**:
  - `charts/kalypso-grafana/Chart.yaml` - grafana 의존성
  - `charts/kalypso-grafana/values.yaml` - cross-namespace datasources

  **Cross-Namespace Datasources**:
  ```yaml
  datasources:
    - name: Mimir
      type: prometheus
      url: http://mimir-distributed-gateway.mimir.svc.cluster.local:80/prometheus
      
    - name: Tempo
      type: tempo
      url: http://tempo-distributed-query-frontend.tempo.svc.cluster.local:3100
      
    - name: Loki
      type: loki
      url: http://loki-gateway.loki.svc.cluster.local:80
      
    - name: Pyroscope
      type: grafana-pyroscope-datasource
      url: http://pyroscope.pyroscope.svc.cluster.local:4040
  ```

  **Parallelizable**: NO (Task 5, 6, 7, 8 완료 후)

  **References**:
  - `values/grafana-values.yaml` - datasources 설정 참고

  **Acceptance Criteria**:
  - [ ] `helm lint charts/kalypso-grafana` → 0 errors
  - [ ] 4개 datasource 모두 cross-namespace URL

  **Commit**: YES
  - Message: `feat(chart): add kalypso-grafana chart with cross-namespace datasources`
  - Files: `charts/kalypso-grafana/*`

---

- [x] 10. ArgoCD ApplicationSet 생성

  **What to do**:
  - `argocd/project.yaml` - ArgoCD Project 정의
  - `argocd/applicationset.yaml` - ApplicationSet (모든 charts)

  **ApplicationSet with Sync Waves**:
  ```yaml
  apiVersion: argoproj.io/v1alpha1
  kind: ApplicationSet
  metadata:
    name: kalypso-infra
    namespace: argocd
  spec:
    generators:
      - list:
          elements:
            - name: otel
              namespace: otel-system
              path: charts/kalypso-otel
              wave: "1"
            - name: istio
              namespace: istio-system
              path: charts/kalypso-istio
              wave: "2"
            - name: minio
              namespace: minio
              path: charts/kalypso-minio
              wave: "3"
            - name: mimir
              namespace: mimir
              path: charts/kalypso-mimir
              wave: "4"
            - name: tempo
              namespace: tempo
              path: charts/kalypso-tempo
              wave: "4"
            - name: loki
              namespace: loki
              path: charts/kalypso-loki
              wave: "4"
            - name: pyroscope
              namespace: pyroscope
              path: charts/kalypso-pyroscope
              wave: "5"
            - name: grafana
              namespace: grafana
              path: charts/kalypso-grafana
              wave: "6"
    template:
      metadata:
        name: 'kalypso-{{name}}'
        annotations:
          argocd.argoproj.io/sync-wave: '{{wave}}'
      spec:
        project: kalypso-infra
        source:
          repoURL: <GIT_REPO_URL>
          targetRevision: HEAD
          path: '{{path}}'
        destination:
          server: https://kubernetes.default.svc
          namespace: '{{namespace}}'
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
          syncOptions:
            - CreateNamespace=true
  ```

  **Parallelizable**: NO (모든 Chart 완료 후)

  **References**:
  - ArgoCD ApplicationSet: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/

  **Acceptance Criteria**:
  - [ ] `kubectl apply --dry-run=client -f argocd/` → 유효한 YAML
  - [ ] Sync Wave 순서: otel(1) → istio(2) → minio(3) → mimir/tempo/loki(4) → pyroscope(5) → grafana(6)
  - [ ] `CreateNamespace=true` 설정됨

  **Commit**: YES
  - Message: `feat(argocd): add ApplicationSet for multi-namespace deployment`
  - Files: `argocd/*`

---

- [x] 11. Dockerfile + README 생성

  **What to do**:
  - `docker/ebpf-profiler/Dockerfile` - OTel eBPF Profiler 이미지 빌드
  - `README.md` - 설치 가이드

  **Dockerfile** (Grafana 공식 예제 기반):
  ```dockerfile
  FROM ubuntu:22.04 as builder
  RUN apt-get update && apt-get -y install wget gcc
  # AMD64
  RUN wget https://go.dev/dl/go1.22.10.linux-amd64.tar.gz
  RUN tar -C /usr/local -xzf go1.22.10.linux-amd64.tar.gz
  # 고정 버전 (프로토콜 호환성)
  RUN wget https://github.com/open-telemetry/opentelemetry-ebpf-profiler/archive/19cb11e6bf00c04e4f8d793e944e71478f9608d9.tar.gz
  RUN mkdir /profiler && tar --strip-components=1 -C /profiler -xzf *.tar.gz
  WORKDIR /profiler
  RUN /usr/local/go/bin/go build .

  FROM ubuntu:22.04
  RUN apt-get update && apt-get install -y linux-headers-generic
  COPY --from=builder /profiler/ebpf-profiler /usr/local/bin/
  ENTRYPOINT ["/usr/local/bin/ebpf-profiler"]
  ```

  **README 내용**:
  - 아키텍처 개요 (8 Charts + ArgoCD)
  - 사전 요구사항: ArgoCD, Linux 노드 (eBPF)
  - 설치 방법:
    1. ArgoCD에 repo 등록
    2. `kubectl apply -f argocd/`
  - eBPF Profiler 이미지 빌드 방법
  - ARM64 지원 방법
  - 개별 Chart 설치 방법 (ArgoCD 없이)

  **Parallelizable**: YES (Task 10과 병렬)

  **Acceptance Criteria**:
  - [ ] Dockerfile 유효
  - [ ] README에 ArgoCD 설치 방법 포함
  - [ ] README에 개별 Chart 설치 방법 포함

  **Commit**: YES
  - Message: `docs: add Dockerfile for eBPF profiler and installation README`
  - Files: `docker/ebpf-profiler/Dockerfile`, `README.md`

---

- [x] 12. 전체 검증

  **What to do**:
  - 모든 Chart `helm lint` 실행
  - 모든 Chart `helm dependency build` 실행
  - 모든 Chart `helm template` 실행
  - ArgoCD ApplicationSet 유효성 검증

  **Verification Commands**:
  ```bash
  # 모든 Chart lint
  for chart in charts/kalypso-*; do
    helm lint $chart
  done

  # 모든 Chart dependency build
  for chart in charts/kalypso-*; do
    helm dependency build $chart
  done

  # 모든 Chart template
  for chart in charts/kalypso-*; do
    helm template test $chart
  done

  # ArgoCD 검증
  kubectl apply --dry-run=client -f argocd/
  ```

  **Parallelizable**: NO (마지막 작업)

  **Acceptance Criteria**:
  - [ ] 8개 Chart 모두 `helm lint` 통과
  - [ ] 8개 Chart 모두 `helm template` 성공
  - [ ] ArgoCD ApplicationSet YAML 유효
  - [ ] Cross-namespace URL 모두 올바르게 설정됨

  **Commit**: YES
  - Message: `chore: verify all charts and add dependency locks`
  - Files: `charts/*/Chart.lock`, `charts/*/charts/*.tgz`

---

## Commit Strategy

| After Task | Message | Files |
|------------|---------|-------|
| 2 | `feat(chart): add kalypso-otel chart` | charts/kalypso-otel/* |
| 3 | `feat(chart): add kalypso-istio chart` | charts/kalypso-istio/* |
| 4 | `feat(chart): add kalypso-minio chart` | charts/kalypso-minio/* |
| 5 | `feat(chart): add kalypso-mimir chart` | charts/kalypso-mimir/* |
| 6 | `feat(chart): add kalypso-tempo chart` | charts/kalypso-tempo/* |
| 7 | `feat(chart): add kalypso-loki chart` | charts/kalypso-loki/* |
| 8 | `feat(chart): add kalypso-pyroscope chart` | charts/kalypso-pyroscope/* |
| 9 | `feat(chart): add kalypso-grafana chart` | charts/kalypso-grafana/* |
| 10 | `feat(argocd): add ApplicationSet` | argocd/* |
| 11 | `docs: add Dockerfile and README` | docker/*, README.md |
| 12 | `chore: verify all charts` | charts/*/Chart.lock |

---

## Success Criteria

### Verification Commands
```bash
# 전체 Chart lint
for chart in charts/kalypso-*; do helm lint $chart; done

# Cross-namespace URL 확인
grep -r "svc.cluster.local" charts/

# ArgoCD 검증
kubectl apply --dry-run=client -f argocd/
```

### Final Checklist
- [x] 8개 Chart 모두 존재 및 lint 통과
- [x] 모든 S3 backend가 `minio.minio.svc.cluster.local:9000` 사용
- [x] 모든 datasource가 cross-namespace URL 사용
- [x] Alloy 미포함 확인
- [x] Kafka 미포함/비활성화 확인
- [x] OTel eBPF 프로파일러 설정 포함
- [x] ArgoCD ApplicationSet Sync Wave 순서 올바름
- [x] README에 설치 가이드 포함

---

## Additional Testing Tasks (User Request)

- [x] 13. Create Kind cluster with podman

  **What to do**:
  - Create Kind cluster using podman as container runtime
  - Verify cluster is running
  - Install ArgoCD in the cluster

  **Commands**:
  ```bash
  # Create Kind cluster
  kind create cluster --name kalypso-test
  
  # Verify cluster
  kubectl cluster-info
  kubectl get nodes
  
  # Install ArgoCD
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  ```

  **Parallelizable**: NO

  **Acceptance Criteria**:
  - [ ] Kind cluster created and running
  - [ ] kubectl can connect to cluster
  - [ ] ArgoCD installed in argocd namespace

  **Commit**: NO (testing only)

---

- [x] 14. Deploy Kalypso charts to Kind cluster

  **What to do**:
  - Update repoURL in applicationset.yaml (use local path or git repo)
  - Build eBPF profiler image (skip if ARM64 issues)
  - Apply ArgoCD project and applicationset
  - Monitor deployment progress

  **Commands**:
  ```bash
  # Option 1: Use local charts (no git repo needed)
  # Modify applicationset to use local paths
  
  # Option 2: Push to git and use repo URL
  # Update argocd/applicationset.yaml with actual repo URL
  
  # Apply ArgoCD resources
  kubectl apply -f argocd/project.yaml
  kubectl apply -f argocd/applicationset.yaml
  
  # Monitor
  kubectl get applications -n argocd
  kubectl get pods -A
  ```

  **Parallelizable**: NO (depends on Task 13)

  **Acceptance Criteria**:
  - [ ] ArgoCD applications created
  - [ ] Pods starting in all namespaces
  - [ ] No critical errors in ArgoCD app status

  **Commit**: NO (testing only)

  **Note**: eBPF profiler may fail on ARM64 - acceptable per user request

---

- [x] 15. Verify deployment and document results

  **What to do**:
  - Check all pods are running (except possibly eBPF profiler on ARM64)
  - Verify MinIO buckets created
  - Verify Grafana datasources configured
  - Port-forward to Grafana and verify UI accessible
  - Document any issues found

  **Commands**:
  ```bash
  # Check pods
  kubectl get pods -A | grep -E "(minio|grafana|mimir|tempo|loki|pyroscope|istio|otel)"
  
  # Check MinIO
  kubectl port-forward -n minio svc/kalypso-minio 9001:9001
  
  # Check Grafana
  kubectl port-forward -n grafana svc/kalypso-grafana 3000:80
  ```

  **Parallelizable**: NO (depends on Task 14)

  **Acceptance Criteria**:
  - [ ] Core components running (MinIO, Grafana, Mimir, Tempo, Loki)
  - [ ] Grafana UI accessible
  - [ ] Datasources configured in Grafana
  - [ ] Issues documented in notepad

  **Commit**: NO (testing only)

---

