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
- ✅ RHAII on XKS repository cloned

---

## Installation Method

We use the **RHAII on XKS** repository as the official and recommended method for installing operators.

**Why RHAII on XKS?**
- Official Red Hat repository for GKE deployments
- Tested operator versions and configurations
- Automated installation via Makefile
- Consistent with Red Hat support path

**Repository:** https://github.com/opendatahub-io/rhaii-on-xks

---

## Step-by-Step Installation

### Step 1: Clone RHAII on XKS Repository

```bash
# Navigate to workspace directory
cd ~/workspace

# Check if repository already exists
if [ ! -d "rhaii-on-xks" ]; then
  echo "Cloning RHAII on XKS repository..."
  git clone https://github.com/opendatahub-io/rhaii-on-xks.git
else
  echo "RHAII on XKS repository already exists"
  cd rhaii-on-xks
  git pull  # Update to latest
fi

# Navigate into repository
cd rhaii-on-xks
```

**Expected output:**
```
Cloning into 'rhaii-on-xks'...
remote: Enumerating objects: ...
```

---

### Step 2: Configure Red Hat Registry Credentials

The RHAII on XKS repository will guide you through credential setup. Follow their documentation for:

1. Creating Red Hat registry service account
2. Downloading pull secret
3. Applying secret to cluster

**Reference:** See RHAII on XKS README for detailed credential setup.

---

### Step 3: Deploy All Operators

```bash
# Ensure you're in the rhaii-on-xks directory
cd ~/workspace/rhaii-on-xks

# Deploy all required operators
make deploy-all
```

**What this does:**
1. Deploys cert-manager
2. Deploys Red Hat Service Mesh (Istio)
3. Deploys KServe with dependencies
4. Deploys LeaderWorkerSet controller

**Expected duration:** ~8-10 minutes

**Expected output:**
```
Deploying cert-manager...
✓ cert-manager deployed successfully

Deploying Istio (Service Mesh)...
✓ Istio deployed successfully

Deploying KServe...
✓ KServe deployed successfully

Deploying LWS...
✓ LWS deployed successfully

All operators deployed!
```

---

### Step 4: Verify Operator Status

```bash
# Check status via RHAII on XKS
make status

# Or manually verify each operator
kubectl get pods -n cert-manager
kubectl get pods -n istio-system
kubectl get pods -n kserve
kubectl get pods -n lws-system
```

**Success criteria:**
All pods should be in `Running` state:

```
NAMESPACE       NAME                                    READY   STATUS
cert-manager    cert-manager-...                        1/1     Running
cert-manager    cert-manager-cainjector-...             1/1     Running
cert-manager    cert-manager-webhook-...                1/1     Running
istio-system    istiod-...                              1/1     Running
istio-system    istio-ingressgateway-...                1/1     Running
kserve          kserve-controller-manager-...           1/1     Running
lws-system      lws-controller-manager-...              1/1     Running
```

---

### Step 5: Comprehensive Verification (Recommended)

Use the verification script from the rhaii-on-xks-gke repository:

```bash
# Navigate to rhaii-on-xks-gke repository
cd ~/workspace/rhaii-on-xks-gke

# Run operator verification
./scripts/verify-deployment.sh --operators-only
```

**This verifies:**
- ✅ All operator pods running
- ✅ cert-manager webhook ready
- ✅ Istio control plane ready
- ✅ KServe controller ready
- ✅ Gateway has external IP assigned

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

## Operator Details

### cert-manager

**Purpose:** Automated TLS certificate management

**Namespace:** `cert-manager`

**Components:**
- cert-manager controller
- cert-manager-cainjector
- cert-manager-webhook

**Verification:**
```bash
kubectl get pods -n cert-manager
kubectl get certificates --all-namespaces
```

---

### Red Hat OpenShift Service Mesh (Istio)

**Purpose:** Service mesh for traffic routing, mTLS, and observability

**Namespace:** `istio-system`

**Components:**
- istiod (control plane)
- istio-ingressgateway (ingress gateway for external traffic)

**Verification:**
```bash
kubectl get pods -n istio-system
kubectl get gateway --all-namespaces
kubectl get virtualservice --all-namespaces
```

**Check Gateway IP:**
```bash
kubectl get svc istio-ingressgateway -n istio-system
```

---

### KServe

**Purpose:** Serverless inference serving platform

**Namespace:** `kserve`

**Components:**
- kserve-controller-manager

**Custom Resources:**
- LLMInferenceService (for vLLM deployments)
- InferenceService (standard KServe CRD)
- InferencePool (for distributed serving)

**Verification:**
```bash
kubectl get pods -n kserve
kubectl api-resources | grep kserve
```

---

### LeaderWorkerSet (LWS)

**Purpose:** Distributed workload orchestration

**Namespace:** `lws-system`

**Components:**
- lws-controller-manager

**Verification:**
```bash
kubectl get pods -n lws-system
kubectl get crd | grep leaderworkerset
```

---

## Troubleshooting

### Operator Pods Not Running

**Check pod status:**
```bash
kubectl get pods -n cert-manager
kubectl get pods -n istio-system
kubectl get pods -n kserve
kubectl get pods -n lws-system
```

**View pod logs:**
```bash
kubectl logs -n <namespace> <pod-name>
```

**Common issues:**
1. **Image pull errors:** Verify pull secret applied correctly
2. **Pending pods:** Check node resources (CPU/memory)
3. **CrashLoopBackOff:** Check logs for specific errors

---

### Gateway Not Getting External IP

**Symptom:**
```bash
kubectl get svc istio-ingressgateway -n istio-system
# EXTERNAL-IP shows <pending>
```

**Solution:**
Wait 2-3 minutes for GCP load balancer provisioning.

**If still pending after 5 minutes:**
```bash
# Check service events
kubectl describe svc istio-ingressgateway -n istio-system

# Check GCP quotas for load balancers
gcloud compute project-info describe --project=YOUR_PROJECT
```

---

### cert-manager Webhook Not Ready

**Symptom:**
```
Error: webhook validation failed
```

**Solution:**
```bash
# Wait for webhook pods to be ready
kubectl wait --for=condition=ready pod -l app=webhook -n cert-manager --timeout=300s

# Restart webhook if needed
kubectl rollout restart deployment cert-manager-webhook -n cert-manager
```

---

### KServe Controller Issues

**Symptom:**
LLMInferenceService resources not being created

**Check controller logs:**
```bash
kubectl logs -n kserve deployment/kserve-controller-manager -f
```

**Common fixes:**
1. Verify Istio is running first
2. Check CRD installation: `kubectl get crd | grep kserve`
3. Restart controller: `kubectl rollout restart deployment/kserve-controller-manager -n kserve`

---

## Uninstallation (If Needed)

**To remove all operators:**
```bash
cd ~/workspace/rhaii-on-xks
make uninstall-all
```

**Warning:** This will delete all operator resources. Ensure no workloads are running first.

**Manual cleanup if needed:**
```bash
# Delete operators in reverse order
kubectl delete namespace lws-system
kubectl delete namespace kserve
kubectl delete namespace istio-system
kubectl delete namespace cert-manager
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

**Operator Versions:**
- cert-manager: Latest stable
- Istio (via sail-operator): Red Hat OpenShift Service Mesh
- KServe: v0.15
- LWS: Latest stable

**Support:**
- RHAII on XKS issues: https://github.com/opendatahub-io/rhaii-on-xks/issues
- Operator-specific: See individual operator documentation

---

**Questions?** See [FAQ](faq.md) or [Troubleshooting](troubleshooting.md)
