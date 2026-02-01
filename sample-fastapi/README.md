# sample-fastapi

LGTM (Loki, Grafana, Tempo, Mimir) + Pyroscope 테스트용 FastAPI 샘플 앱입니다.  
OTel Operator Python auto-instrumentation을 적용하여 traces/metrics를 OTel Collector로 전송합니다.

## 프로젝트 구조

```
sample-fastapi/
├── pyproject.toml      # uv project (fastapi, uvicorn)
├── Dockerfile          # uv 기반 빌드
├── src/
│   └── sample_fastapi/
│       ├── __init__.py
│       └── main.py     # FastAPI 앱 진입점
└── manifest/           # K8s manifests (ArgoCD 미적용)
    ├── namespace.yaml       # namespace: applications
    ├── instrumentation.yaml # OTel Python Instrumentation CR
    ├── deployment.yaml      # inject-python: "true"
    ├── service.yaml
    └── kustomization.yaml
```

## 사전 요구사항

- Python 3.11+
- [uv](https://docs.astral.sh/uv/) (`brew install uv`)
- Podman (이미지 빌드 시) (`brew install podman`)
- Kubernetes 클러스터 + OTel Operator + OTel Collector (배포 시)

## 로컬 실행

```bash
# 의존성 설치
uv sync

# 서버 실행
uv run uvicorn sample_fastapi.main:app --reload --host 0.0.0.0 --port 8000
```

- http://localhost:8000 - API
- http://localhost:8000/docs - Swagger UI

## 이미지 빌드

```bash
podman build -t localhost/sample-fastapi:latest .
```

Kind 클러스터 사용 시 이미지 로드:

```bash
# 이미지 tar로 저장 후 로드
podman save localhost/sample-fastapi:latest -o /tmp/sample-fastapi.tar
kind load image-archive /tmp/sample-fastapi.tar --name kind
rm /tmp/sample-fastapi.tar
```

## Kubernetes 배포

LGTM 스택(otel, tempo, mimir 등)이 이미 배포된 클러스터에서:

```bash
# 1. 이미지 빌드 및 로드 (Kind)
podman build -t localhost/sample-fastapi:latest .
podman save localhost/sample-fastapi:latest -o /tmp/sample-fastapi.tar
kind load image-archive /tmp/sample-fastapi.tar --name kind
rm /tmp/sample-fastapi.tar

# 2. manifest 배포
kubectl apply -k manifest/
```

배포 순서: `Instrumentation` CR → `Deployment` (Kustomize가 자동 처리)

## OTel Instrumentation

- **Annotation**: `instrumentation.opentelemetry.io/inject-python: "true"`
- **Endpoint**: `kalypso-otel-collector.otel-system.svc.cluster.local:4318` (HTTP/protobuf)
- **데이터 흐름**: sample-fastapi → OTel Collector → Tempo (traces), Mimir (metrics)

## API 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| GET | / | 루트 |
| GET | /health | 헬스체크 |
| GET | /items/{item_id} | 샘플 (tracing 테스트) |

## 포트포워드

```bash
kubectl port-forward -n applications svc/sample-fastapi 8000:80
# http://localhost:8000
```
