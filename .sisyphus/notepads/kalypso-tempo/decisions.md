# Kalypso Tempo Chart - Architectural Decisions

## Dependency Management
- **Decision**: Use tempo-distributed 1.7.0 from Grafana official Helm charts
- **Rationale**: Latest stable version with comprehensive distributed tracing support
- **Repository**: https://grafana.github.io/helm-charts

## MinIO Integration
- **Decision**: Disable internal MinIO, use cross-namespace kalypso-minio
- **Rationale**: Centralized MinIO instance reduces resource overhead and simplifies management
- **Configuration**: Explicit S3 endpoint pointing to minio.minio namespace

## Development Sizing
- **Decision**: All replicas set to 1, replication_factor set to 1
- **Rationale**: Minimal resource footprint for development/testing environments
- **Note**: Should be increased for production deployments

## Protocol Support
- **Decision**: Enable OTLP (HTTP + gRPC) and Jaeger Thrift HTTP
- **Rationale**: Covers most common instrumentation libraries and existing Jaeger deployments
- **Disabled**: Zipkin and OpenCensus (less commonly used in this stack)

## Persistence
- **Decision**: Ingester persistence disabled
- **Rationale**: Development environment with external S3 backend handles durability
- **Note**: Should be enabled for production with appropriate storage class
