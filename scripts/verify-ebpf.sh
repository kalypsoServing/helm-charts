#!/usr/bin/env bash
set -euo pipefail

# eBPF support verification script for Kalypso Infrastructure
# Checks kernel capabilities required by OTel eBPF profiler

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}PASS${NC}  $*"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}FAIL${NC}  $*"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}WARN${NC}  $*"; WARN=$((WARN+1)); }

echo "============================================"
echo " eBPF Support Verification"
echo "============================================"
echo ""

# Determine execution mode: run checks on a K8s node or locally
if kubectl get nodes &>/dev/null 2>&1; then
  MODE="k8s"
  echo "Mode: Kubernetes cluster detected"
  NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  echo "Node: ${NODE}"
  echo ""

  # Create a privileged debug pod to run checks on the node
  POD_NAME="ebpf-verify-$$"
  cleanup() {
    kubectl delete pod "${POD_NAME}" --ignore-not-found --grace-period=0 --force &>/dev/null || true
  }
  trap cleanup EXIT

  echo "Creating privileged verification pod..."
  if ! kubectl run "${POD_NAME}" \
    --image=busybox:latest \
    --restart=Never \
    --overrides='{
      "spec": {
        "hostPID": true,
        "hostNetwork": true,
        "containers": [{
          "name": "ebpf-verify",
          "image": "busybox:latest",
          "command": ["sleep", "300"],
          "securityContext": {
            "privileged": true
          },
          "volumeMounts": [
            {"name": "sys", "mountPath": "/sys", "readOnly": true},
            {"name": "proc", "mountPath": "/host-proc", "readOnly": true}
          ]
        }],
        "volumes": [
          {"name": "sys", "hostPath": {"path": "/sys"}},
          {"name": "proc", "hostPath": {"path": "/proc"}}
        ]
      }
    }'; then
    echo -e "${RED}Failed to create verification pod.${NC}"
    exit 1
  fi

  echo "Waiting for verification pod to be ready..."
  if ! kubectl wait --for=condition=ready "pod/${POD_NAME}" --timeout=120s; then
    echo -e "${RED}Verification pod did not become ready. Pod status:${NC}"
    kubectl describe pod "${POD_NAME}" | tail -20
    exit 1
  fi

  run_check() {
    kubectl exec "${POD_NAME}" -- sh -c "$1" 2>/dev/null
  }
else
  MODE="local"
  echo "Mode: Local (no Kubernetes cluster)"
  echo ""

  run_check() {
    sh -c "$1" 2>/dev/null
  }
fi

# --- Check 1: Kernel version ---
echo "[1/6] Kernel Version (5.x+ required for eBPF)"
KERNEL=$(run_check "uname -r" || echo "unknown")
MAJOR=$(echo "${KERNEL}" | cut -d. -f1)
if [[ "${MAJOR}" -ge 5 ]] 2>/dev/null; then
  pass "Kernel ${KERNEL} (>= 5.x)"
else
  fail "Kernel ${KERNEL} (< 5.x, eBPF features limited)"
fi

# --- Check 2: BPF JIT ---
echo "[2/6] BPF JIT Compiler"
if [[ "${MODE}" == "k8s" ]]; then
  JIT=$(run_check "cat /host-proc/sys/net/core/bpf_jit_enable" || echo "")
else
  JIT=$(run_check "cat /proc/sys/net/core/bpf_jit_enable" || echo "")
fi
if [[ "${JIT}" == "1" ]] || [[ "${JIT}" == "2" ]]; then
  pass "BPF JIT enabled (${JIT})"
else
  fail "BPF JIT not enabled (value: '${JIT}')"
fi

# --- Check 3: Tracing filesystem ---
echo "[3/6] Tracing Filesystem (/sys/kernel/debug/tracing/)"
TRACING=$(run_check "ls /sys/kernel/debug/tracing/available_events 2>/dev/null && echo 'ok'" || echo "")
if [[ "${TRACING}" == *"ok"* ]]; then
  pass "/sys/kernel/debug/tracing/ accessible"
else
  # Also check tracefs mount
  TRACEFS=$(run_check "ls /sys/kernel/tracing/available_events 2>/dev/null && echo 'ok'" || echo "")
  if [[ "${TRACEFS}" == *"ok"* ]]; then
    pass "/sys/kernel/tracing/ accessible (tracefs)"
  else
    fail "/sys/kernel/debug/tracing/ not accessible (Kind limitation)"
  fi
fi

# --- Check 4: Cgroup filesystem ---
echo "[4/6] Cgroup Filesystem (/sys/fs/cgroup/)"
CGROUP=$(run_check "ls /sys/fs/cgroup/ 2>/dev/null | head -1" || echo "")
if [[ -n "${CGROUP}" ]]; then
  # Check cgroup version
  CGROUPV2=$(run_check "test -f /sys/fs/cgroup/cgroup.controllers && echo 'v2'" || echo "")
  if [[ "${CGROUPV2}" == "v2" ]]; then
    pass "cgroup v2 available"
  else
    pass "cgroup v1 available"
  fi
else
  fail "/sys/fs/cgroup/ not accessible"
fi

# --- Check 5: Security filesystem ---
echo "[5/6] Security Filesystem (/sys/kernel/security/)"
SECURITY=$(run_check "ls /sys/kernel/security/ 2>/dev/null | head -1" || echo "")
if [[ -n "${SECURITY}" ]]; then
  pass "/sys/kernel/security/ accessible"
else
  warn "/sys/kernel/security/ not accessible (may not be required)"
fi

# --- Check 6: Privileged pod support ---
echo "[6/6] Privileged Pod Execution"
if [[ "${MODE}" == "k8s" ]]; then
  # If we got here, the privileged pod is running
  PRIV=$(run_check "cat /host-proc/1/status 2>/dev/null | head -1" || echo "")
  if [[ -n "${PRIV}" ]]; then
    pass "Privileged pod can access host PID namespace"
  else
    fail "Privileged pod cannot access host processes"
  fi
else
  warn "Skipped (no Kubernetes cluster)"
fi

# --- Summary ---
echo ""
echo "============================================"
echo " Results: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"
echo "============================================"

if [[ ${FAIL} -eq 0 ]]; then
  echo -e "${GREEN}All critical checks passed. eBPF profiling should work.${NC}"
  exit 0
else
  echo -e "${RED}Some checks failed. eBPF profiling may not work correctly.${NC}"
  echo ""
  echo "If running on Kind, consider switching to Colima + K3s:"
  echo "  make cluster-colima"
  exit 1
fi
