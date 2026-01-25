# Kalypso-Loki Chart Decisions

## Deployment Mode: SimpleScalable
- Chosen over Monolithic for better scalability
- Separates read, write, and backend concerns
- Allows independent scaling of components

## S3 Backend Selection
- Chosen over filesystem for production-ready persistence
- Leverages existing kalypso-minio infrastructure
- Cross-namespace access via Kubernetes DNS

## Replica Count: 1
- Minimal deployment for development/testing
- Can be increased in values overrides for production
- Replication factor set to 1 to match single replica

## Bucket Strategy
- Single loki-bucket for chunks, ruler, and admin
- Simplifies MinIO bucket management
- Can be split into separate buckets if needed

## Loki Version: 6.0.0
- Latest stable version at time of creation
- Supports SimpleScalable mode and S3 storage
- Compatible with Kubernetes 1.24+
