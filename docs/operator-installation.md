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

## Istio CNI Verification (Critical Requirement)

**⚠️ CRITICAL:** This deployment requires Istio CNI to be enabled during operator installation.

**What is Istio CNI:**
Istio CNI is a container network plugin that enables proper sidecar injection and mTLS communication. It's required for the EPP (External Processing Protocol) scheduler to communicate with the Istio Gateway.

**Why it's critical:**
- EPP scheduler needs Istio sidecar for mTLS communication with Gateway
- ext_proc filter uses gRPC over mTLS to route requests for cache awareness
- Without CNI, init container network conflicts prevent proper mTLS setup
- Cache-aware routing will fail without CNI

**Installation:**
Istio CNI is automatically installed when you run `make deploy-all` from the rhaii-on-xks repository. The RHAII operators include Istio with CNI enabled by default.

**Verify Istio CNI is enabled:**

```bash
# Check CNI DaemonSet exists in istio-system namespace
kubectl get daemonset -n istio-system istio-cni-node

# Expected output (shows CNI running on all nodes):
# NAME             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
# istio-cni-node   3         3         3       3            3

# Verify CNI pods are running
kubectl get pods -n istio-system -l k8s-app=istio-cni-node

# Check CNI configuration
kubectl get configmap -n istio-system istio-cni-config
```

**If CNI is missing:**

The rhaii-on-xks installation should have enabled CNI automatically. If it's missing:

```bash
# Re-run operator installation
cd /path/to/rhaii-on-xks
make deploy-all

# Verify CNI is now present
kubectl get daemonset -n istio-system istio-cni-node
```

**Important:** Do not proceed with deployment if CNI is not running. EPP scheduler mTLS communication will fail.

**Time:** ~1 minute verification

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
