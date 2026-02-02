# Grafana Alloy - 프로파일링 수집기

Alloy는 프로파일링 데이터 전용 수집기로, 애플리케이션과 Pyroscope 서버 사이의 프록시 역할을 한다.

## 아키텍처

```
App (Pyroscope SDK)
  │
  │  HTTP POST /ingest
  ▼
Alloy (alloy ns, :4040)
  ├─ pyroscope.receive_http  ← SDK push 수신
  ├─ pyroscope.scrape        ← annotation 기반 pprof pull
  └─ pyroscope.write         ── ▶ Pyroscope Distributor (pyroscope ns, :4040)
```

## 배포

```bash
kustomize build manifests/alloy | kubectl apply -f -
```

## 관측 데이터를 Alloy로 보내는 방법

Alloy에 프로파일 데이터를 전송하는 방법은 **Push(SDK)** 와 **Pull(annotation)** 두 가지다.

---

### 방법 1: Push — Pyroscope SDK (권장)

애플리케이션에서 Pyroscope SDK가 Alloy의 HTTP 엔드포인트로 프로파일을 직접 전송한다.

#### 엔드포인트

```
http://alloy.alloy.svc.cluster.local:4040
```

#### Python (OTel autoinstrumentation + pyroscope-io)

Instrumentation CR에 환경변수를 설정하면 된다. 코드 변경은 필요 없다.

```yaml
# instrumentation.yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: instrumentation
  namespace: applications
spec:
  python:
    image: sky5367/otel-autoinstrumentation-python-pyroscope:0.60b0-pyroscope2
    env:
      - name: PYROSCOPE_SERVER_ADDRESS
        value: "http://alloy.alloy.svc.cluster.local:4040"
```

내부적으로 `pyroscope_bootstrap.py`가 이 환경변수를 읽어 `pyroscope.configure(server_address=...)` 를 호출한다.

#### Python (수동 설정)

OTel autoinstrumentation을 사용하지 않는 경우, 앱 코드에서 직접 설정한다.

```python
import pyroscope

pyroscope.configure(
    application_name="my-app",
    server_address="http://alloy.alloy.svc.cluster.local:4040",
    tags={
        "service_name": "my-app",
        "env": "production",
    },
)
```

#### Go

```go
import "github.com/grafana/pyroscope-go"

pyroscope.Start(pyroscope.Config{
    ApplicationName: "my-app",
    ServerAddress:   "http://alloy.alloy.svc.cluster.local:4040",
    Tags:            map[string]string{"env": "production"},
})
```

#### Java

```java
PyroscopeAgent.start(
    new Config.Builder()
        .setApplicationName("my-app")
        .setServerAddress("http://alloy.alloy.svc.cluster.local:4040")
        .build()
);
```

#### 환경변수로 주입 (언어 무관)

Deployment에 환경변수만 추가해도 된다. SDK가 `PYROSCOPE_SERVER_ADDRESS`를 자동으로 읽는다.

```yaml
# deployment.yaml
spec:
  template:
    spec:
      containers:
        - name: my-app
          env:
            - name: PYROSCOPE_SERVER_ADDRESS
              value: "http://alloy.alloy.svc.cluster.local:4040"
```

---

### 방법 2: Pull — Annotation 기반 스크래핑

pprof 엔드포인트를 노출하는 애플리케이션(Go 등)의 경우, Pod에 annotation을 추가하면 Alloy가 자동으로 스크래핑한다.

#### Deployment annotation 추가

```yaml
spec:
  template:
    metadata:
      annotations:
        # CPU 프로파일링 활성화
        profiles.grafana.com/cpu.scrape: "true"
        profiles.grafana.com/cpu.port: "8080"

        # 메모리 프로파일링 활성화
        profiles.grafana.com/memory.scrape: "true"
        profiles.grafana.com/memory.port: "8080"

        # Goroutine 프로파일링 (Go)
        profiles.grafana.com/goroutine.scrape: "true"
        profiles.grafana.com/goroutine.port: "8080"
```

Alloy의 `discovery.relabel` 이 `profiles.grafana.com/cpu.scrape: "true"` annotation이 있는 Pod를 자동 감지하고, 지정된 포트의 pprof 엔드포인트(`/debug/pprof/`)를 스크래핑한다.

#### Go 애플리케이션 pprof 노출 예시

```go
import _ "net/http/pprof"

go func() {
    http.ListenAndServe(":8080", nil)
}()
```

---

## 데이터 흐름 확인

### 1. Alloy Pod 상태 확인

```bash
kubectl get pods -n alloy
```

### 2. Alloy UI에서 파이프라인 상태 확인

```bash
kubectl port-forward -n alloy svc/alloy 12345:12345
# 브라우저에서 http://localhost:12345 접속
```

컴포넌트 그래프에서 `pyroscope.receive_http`, `pyroscope.scrape`, `pyroscope.write`가 모두 녹색(healthy)인지 확인한다.

### 3. Grafana에서 프로파일 데이터 확인

Grafana Explore에서 Pyroscope 데이터소스를 선택하고 다음 쿼리로 확인한다.

```
{service_name="sample-fastapi"}
```

태그 필터도 동작하는지 확인:

```
{service_name="sample-fastapi", http_route="/items/{item_id}", http_method="GET"}
```

### 4. Trace-Profile 연동 확인

Grafana Tempo에서 트레이스를 선택하면, 해당 span 시간대의 Pyroscope 프로파일로 링크가 연결된다.

## 파일 구조

```
manifests/alloy/
├── kustomization.yaml   # Helm chart 배포 정의
├── namespace.yaml       # alloy 네임스페이스
├── alloy-rbac.yaml      # 크로스 네임스페이스 Pod 디스커버리 RBAC
├── values.yaml          # Alloy 파이프라인 설정
└── README.md
```
