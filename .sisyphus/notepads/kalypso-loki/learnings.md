# Kalypso-Loki Chart Learnings

## Cross-Namespace MinIO Integration
- S3 endpoint uses Kubernetes DNS: `minio.minio.svc.cluster.local:9000`
- Pattern: `<service>.<namespace>.svc.cluster.local:<port>`
- Credentials: rootuser/rootpass123 (from kalypso-minio chart)
- Bucket: loki-bucket (pre-created in kalypso-minio)

## SimpleScalable Deployment Mode
- Requires separate read, write, and backend replicas
- Gateway component enabled for HTTP access
- Each component set to 1 replica for minimal deployment
- Replication factor set to 1 (matches single replica setup)

## Storage Configuration
- Type: S3 with s3ForcePathStyle: true (required for MinIO)
- insecure: true (MinIO uses HTTP in cluster)
- Three bucket names configured: chunks, ruler, admin (all point to loki-bucket)
- Schema: v13 with TSDB store

## Helm Dependency Management
- Chart.yaml specifies loki 6.0.0 from https://grafana.github.io/helm-charts
- Condition: loki.enabled allows disabling loki via values
- `helm dependency update` creates Chart.lock and downloads loki chart
- helm lint passes after dependency update

## Chart Structure
- Standard Helm chart layout with Chart.yaml, values.yaml, templates/
- _helpers.tpl includes standard Kubernetes labels and selectors
- No custom templates needed - loki dependency handles all rendering
# Kalypso-Loki Chart Creation - Learnings

## Successful Patterns
- Loki 6.0.0 from Grafana Helm repository integrates cleanly with SimpleScalable deployment mode
- S3 backend configuration with MinIO works with endpoint: `minio.minio.svc.cluster.local:9000`
- Bucket naming convention: `loki-bucket` for both chunks and ruler storage
- Schema config with TSDB store and v13 schema provides modern log storage
- Single replica setup (replicas: 1) suitable for development/testing environments

## Configuration Details
- Deployment Mode: SimpleScalable (read/write/backend separation)
- Auth: Disabled (auth_enabled: false) for simplified setup
- Replication Factor: 1 (suitable for single-node or test clusters)
- S3 Force Path Style: true (required for MinIO compatibility)
- Insecure: true (for local MinIO without TLS)

## Helm Lint Results
- Chart passes validation with 0 failures
- Only informational note: icon is recommended in Chart.yaml (non-blocking)
- All required fields present and valid

## File Structure Created
```
charts/kalypso-loki/
├── Chart.yaml (with loki 6.0.0 dependency)
├── values.yaml (S3 backend config)
├── templates/
│   └── _helpers.tpl (standard Helm template helpers)
└── Chart.lock (auto-generated dependency lock)
```
