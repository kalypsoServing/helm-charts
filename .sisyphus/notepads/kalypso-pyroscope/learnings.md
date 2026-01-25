
## kalypso-pyroscope Chart Creation - $(date +%Y-%m-%d)

### Patterns
- OTel Collector with profiles pipeline: otlp receiver → batch processor → otlp exporter to pyroscope:4040
- Feature gate `--feature-gates=service.profilesSupport` required for profiles pipeline
- eBPF profiler requires: hostPID: true, privileged: true, volume mounts for /sys/kernel/debug, /proc, /sys/fs/cgroup
- Alloy disabled in favor of OTel eBPF profiler approach

### Configuration
- S3 endpoint: minio.minio.svc.cluster.local:9000
- Buckets: pyroscope-data (profiles), pyroscope-admin (metadata)
- OTel Collector image: otel/opentelemetry-collector-contrib:0.129.1
- Pyroscope dependency: 1.5.0 from grafana helm charts

### Files Created
- charts/kalypso-pyroscope/values.yaml
- charts/kalypso-pyroscope/templates/_helpers.tpl
- charts/kalypso-pyroscope/templates/otel-collector-configmap.yaml
- charts/kalypso-pyroscope/templates/otel-collector-deployment.yaml
- charts/kalypso-pyroscope/templates/otel-ebpf-profiler-daemonset.yaml
