# Kalypso Tempo Chart - Learnings

## Cross-Namespace MinIO Integration
- Successfully configured tempo-distributed to use cross-namespace MinIO
- Pattern: `minio.minio.svc.cluster.local:9000` (service.namespace.svc.cluster.local:port)
- Credentials: rootuser/rootpass123 (from kalypso-minio chart)
- Bucket: tempo-bucket (pre-configured in kalypso-minio)

## Development Configuration
- All replicas set to 1 for development environment
- Replication factor set to 1 (matches single replica setup)
- Ingester persistence disabled for development
- Metrics generator disabled to reduce resource usage

## Helm Chart Structure
- Chart.yaml: Declares tempo-distributed 1.7.0 dependency from Grafana repo
- values.yaml: Comprehensive configuration with all components
- _helpers.tpl: Standard Helm template helpers for naming and labels
- Chart dependency update required after initial creation

## S3 Backend Configuration
- Backend: s3
- Insecure: true (for local MinIO without TLS)
- All required S3 parameters configured in storage.trace.s3 section

## Traces Protocol Support
- OTLP HTTP: enabled
- OTLP gRPC: enabled
- Jaeger Thrift HTTP: enabled
- Zipkin: disabled
- OpenCensus: disabled
