FROM python:3.11-slim AS builder

RUN pip install --target /tmp/pyroscope pyroscope-io>=0.8.0 pyroscope-otel>=0.1.0

FROM ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.60b0

# Pyroscope SDK 복사
COPY --from=builder /tmp/pyroscope /autoinstrumentation/

# Bootstrap 파일 복사
COPY pyroscope_bootstrap.py /autoinstrumentation/

# OTel sitecustomize.py 끝에 pyroscope bootstrap import 추가
RUN printf '\nimport pyroscope_bootstrap\n' >> /autoinstrumentation/opentelemetry/instrumentation/auto_instrumentation/sitecustomize.py
