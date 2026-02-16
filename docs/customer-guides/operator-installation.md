# Operator Installation

Install RHAII operators using the official RHAII on XKS repository.

## Overview

**What gets installed:**
- cert-manager (certificate management for TLS)
- Red Hat OpenShift Service Mesh (Istio for traffic routing)
- KServe v0.15 (inference serving platform)
- LeaderWorkerSet (LWS) controller (workload orchestration)

**Time:** ~10 minutes

**Prerequisites:**
- ✅ GKE cluster created and kubectl configured

---

## Installation Instructions

**Use the official RHAII on XKS repository for installation:**

🔗 **https://github.com/opendatahub-io/rhaii-on-xks**

Follow the installation instructions in the RHAII on XKS repository README. The repository provides:
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
  Checking istio-ingressgateway pods... ✅ 1/1 running

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
kubectl logs -n kserve deployment/kserve-controller-manager
kubectl logs -n lws-system deployment/lws-controller-manager
```

---

## Next Steps

After successful operator installation:

1. **Verify deployment:** Run `./scripts/verify-deployment.sh --operators-only`
2. **Deploy workload:**
   - [Single-Model Deployment (TPU)](single-model-deployment-tpu.md)
   - [Single-Model Deployment (GPU)](single-model-deployment-gpu.md)

---

## Reference

**RHAII on XKS Repository:** https://github.com/opendatahub-io/rhaii-on-xks

**Support:**
- RHAII on XKS issues: https://github.com/opendatahub-io/rhaii-on-xks/issues
- General questions: See [FAQ](faq.md) or [Troubleshooting](troubleshooting.md)
