# Operator Installation

Install RHAII operators using the official [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) repository.

## Overview

**What gets installed:**
- cert-manager (certificate management for TLS)
- Red Hat OpenShift Service Mesh (Istio for traffic routing)
- **Istio CNI** (enables sidecar injection for cache-aware routing)
- KServe v0.15 (inference serving platform)
- LeaderWorkerSet (LWS) controller (workload orchestration)

**Time:** ~12 minutes

**Prerequisites:**
- ✅ GKE cluster created and kubectl configured

---

## Installation Instructions

**Use the official repository for installation:**

🔗 **[RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks)**

Follow the installation instructions in the repository README. The repository provides:
- Automated installation via Makefile
- Red Hat registry credential setup
- Tested operator versions and configurations
- Official Red Hat support path

**Quick summary:**
```bash
# Clone the repository
git clone https://github.com/opendatahub-io/rhaii-on-xks.git
cd rhaii-on-xks

# Follow the README for credential setup and installation
make deploy-all

# Verify installation
make status
```

---

## Install Istio CNI (Required for Cache-Aware Routing)

**What is Istio CNI:**
Istio CNI enables sidecar injection for pods with restrictive security contexts (read-only filesystems, no privilege escalation). This is required for the EPP (Endpoint Picker Protocol) scheduler to communicate with the Istio Gateway for cache-aware routing.

**Why it's needed:**
The EPP scheduler requires an Istio sidecar to enable mTLS communication with the Gateway's ext_proc filter. Without Istio CNI, sidecar injection fails due to the EPP's security constraints.

**Installation:**

```bash
# Apply IstioCNI resource
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/istio-cni.yaml

# Wait for CNI to be ready (takes ~1-2 minutes)
kubectl wait --for=condition=Ready istiocni/default --timeout=300s
```

**Verify Istio CNI installation:**

```bash
# Check IstioCNI resource status
kubectl get istiocni

# Expected output:
# NAME      NAMESPACE     PROFILE   READY   STATUS   VERSION       AGE
# default   kube-system             True    Healthy  v1.27-latest  1m

# Check CNI DaemonSet is running
kubectl get daemonset -n kube-system | grep istio-cni-node

# Expected: istio-cni-node should show DESIRED = CURRENT = READY
```

**Time:** ~2 minutes

---

## Verify Installation (Recommended)

Use the verification script from the rhaii-on-xks-gke repository:

```bash
# Navigate to rhaii-on-xks-gke repository
cd ~/workspace/rhaii-on-xks-gke

# Run operator verification
./scripts/verify-deployment.sh --operators-only
```

**Expected output:**
```
=========================================
Operator Verification
=========================================

cert-manager:
  Checking cert-manager pods... ✅ 3/3 running

Istio (Service Mesh):
  Checking istiod pods... ✅ 1/1 running
  Checking inference-gateway pods... ✅ 1/1 running

KServe:
  Checking kserve-controller pods... ✅ 1/1 running

LWS (LeaderWorkerSet):
  Checking lws-controller pods... ✅ 1/1 running

=========================================
✅ All operator checks PASSED
=========================================
```

---

## Troubleshooting

For troubleshooting operator installation issues, refer to:

1. **RHAII on XKS documentation:** https://github.com/opendatahub-io/rhaii-on-xks
2. **Common issues:**
   - Image pull errors → Verify pull secret configured correctly
   - Pending pods → Check node resources and quotas
   - Gateway no external IP → Wait 2-3 minutes for GCP load balancer

**Check operator logs:**
```bash
kubectl logs -n cert-manager deployment/cert-manager
kubectl logs -n istio-system deployment/istiod
kubectl logs -n opendatahub deployment/kserve-controller-manager
kubectl logs -n openshift-lws-operator deployment/openshift-lws-operator
```

---

## Next Steps

After successful operator installation:

1. **Verify deployment:** Run `./scripts/verify-deployment.sh --operators-only`
2. **Deploy workload:**
   - [RHAII Deployment Guide (TPU)](deployment-tpu.md)
   - [RHAII Deployment Guide (GPU)](deployment-gpu.md)

---

## Reference

**RHAII on XKS Repository:** https://github.com/opendatahub-io/rhaii-on-xks

**Support:**
- RHAII on XKS issues: https://github.com/opendatahub-io/rhaii-on-xks/issues
- General questions: See [Troubleshooting](troubleshooting.md)
