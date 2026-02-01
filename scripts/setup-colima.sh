#!/usr/bin/env bash
set -euo pipefail

# Colima + K3s setup script for Kalypso Infrastructure
# Provides a real Linux VM with full eBPF support on ARM64 Mac

CLUSTER_NAME="${COLIMA_PROFILE:-kalypso}"
CPU="${COLIMA_CPU:-10}"
MEMORY="${COLIMA_MEMORY:-16}"
DISK="${COLIMA_DISK:-40}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Check if cluster already exists ---
if colima list 2>/dev/null | grep -q "^${CLUSTER_NAME} .*Running"; then
  warn "Colima profile '${CLUSTER_NAME}' is already running."
  echo "  To delete and recreate: colima delete ${CLUSTER_NAME}"
  echo "  To use existing cluster: export KUBECONFIG=\$(colima kubectl-config ${CLUSTER_NAME} 2>/dev/null || echo ~/.kube/config)"
  exit 0
fi

# --- Create Colima VM with K3s ---
info "Creating Colima VM '${CLUSTER_NAME}' (cpu=${CPU}, memory=${MEMORY}GB, disk=${DISK}GB)..."

colima start "${CLUSTER_NAME}" \
  --cpu "${CPU}" \
  --memory "${MEMORY}" \
  --disk "${DISK}" \
  --runtime containerd \
  --kubernetes \
  --vm-type vz \
  --vz-rosetta \
  --mount-type virtiofs \
  --network-address

info "Colima VM created. Waiting for Kubernetes to be ready..."

# --- Wait for K8s readiness ---
RETRIES=30
for i in $(seq 1 $RETRIES); do
  if kubectl get nodes &>/dev/null; then
    break
  fi
  echo "  Waiting for Kubernetes API... ($i/$RETRIES)"
  sleep 5
done

if ! kubectl get nodes &>/dev/null; then
  error "Kubernetes API did not become ready in time."
  exit 1
fi

info "Kubernetes is ready."
kubectl get nodes -o wide

echo ""
info "Setup complete!"
info "Cluster: ${CLUSTER_NAME}"
info "Context: $(kubectl config current-context)"
echo ""
echo "Next steps:"
echo "  make deploy          # Deploy full stack via ArgoCD"
echo "  make deploy-manual   # Deploy without ArgoCD"
echo "  make verify          # Check pod status"
