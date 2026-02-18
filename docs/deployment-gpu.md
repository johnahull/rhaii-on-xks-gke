# RHAII Deployment Guide (GPU)

Deploy a production vLLM inference service on GPU T4 with prefix caching and intelligent routing.

## Overview

**What you'll deploy:**
- GKE cluster with GPU T4 node pool (3 GPUs total)
- NVIDIA GPU Operator v25.10+ (for GPU injection via CDI)
- RHAII operators (cert-manager, Istio, KServe, LWS)
- 3-replica vLLM inference service with prefix caching enabled
- Cache-aware routing via EnvoyFilter and EPP scheduler
- Security isolation via NetworkPolicies

**Performance:**
- ~18 req/s parallel requests
- ~4.8 req/s serial requests

**Time:** ~50 minutes total

---

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Google Cloud account with billing enabled
- [ ] Project: `YOUR_PROJECT` (or your project) with Owner/Editor role
- [ ] `gcloud` CLI installed and authenticated
- [ ] `kubectl` CLI installed
- [ ] Red Hat registry credentials in `redhat-pull-secret.yaml` (create from `templates/redhat-pull.yaml.template`)
- [ ] HuggingFace token in `huggingface-token-secret.yaml` (create from `templates/huggingface-token.yaml.template`)
- [ ] **GPU T4 quota: 3 GPUs minimum**

**Need help?** See [Prerequisites Guide](prerequisites.md) for detailed setup instructions.

---

## Architecture

This deployment provides high-throughput inference with intelligent request routing.

### Components

**3 vLLM Replicas:**
- Each replica runs on dedicated GPU node (1 T4 GPU per node)
- Prefix caching enabled on all replicas
- Independent model instances with shared architecture

**Cache-Aware Routing:**
- EnvoyFilter routes requests with same prefix to same replica
- Maximizes cache hit rate for improved latency
- EPP (External Processing Protocol) scheduler integration

**Security Isolation:**
- NetworkPolicies restrict traffic between components
- mTLS encryption for all service-to-service communication
- HTTPS with KServe-issued TLS certificates for vLLM endpoints

### Request Flow

```
Client Request: "Translate to Spanish: Hello"
    ↓
Istio Gateway (external IP)
    ↓
EnvoyFilter (hash request prefix)
    ↓
EPP Scheduler (select replica based on hash)
    ↓
Replica 1 (has cached "Translate to Spanish:" prefix)
    ↓
Fast response (~80ms vs ~250ms without cache)
```

### Cache Benefits

**With Prefix Caching:**
- Repeated prefixes cached in KV cache
- ~70% latency reduction on cache hits
- Higher throughput for translation, summarization, Q&A workloads

**Without Prefix Caching:**
- Every token processed from scratch
- Longer latencies for repeated patterns
- Lower overall throughput

---

## Optional: Environment Setup

To avoid repeating `--project`, `--zone`, etc. in every command:

```bash
# One-time setup
cp .envrc.example .envrc
# Edit .envrc with your project ID and zone

# Option A: Install direnv (automatic loading)
# See: https://direnv.net
direnv allow .

# Option B: Manual sourcing (no dependencies)
cp env.sh.example env.sh
# Edit env.sh
source env.sh
```

After setup, you can run commands without flags:
```bash
./scripts/preflight-check.sh --accelerator gpu
# Instead of: ./scripts/preflight-check.sh ... --project YOUR_PROJECT --zone us-central1-a
```

**See:** [Environment Setup Guide](environment-setup.md) for complete instructions.

---

## Step 1: Run Validation Checks (3 minutes)

Validate your environment before creating resources:

```bash
# Navigate to repository
cd /path/to/rhaii-on-xks-gke

# Run preflight check with customer-friendly output
./scripts/preflight-check.sh \
  --accelerator gpu \
  --zone us-central1-a \
  --customer
```

**Success criteria:**
- ✅ All tools installed (gcloud, kubectl, jq)
- ✅ GCP authentication valid
- ✅ Required permissions granted
- ✅ Secrets exist (pull-secret, huggingface-token)
- ✅ GPU T4 quota: 3 GPUs available

**If checks fail:** See troubleshooting output for specific fixes.

---

## Step 2: Create GKE Cluster with GPU Node Pool (15 minutes)

Create a production-ready GKE cluster with GPU T4 node pool:

```bash
# Interactive cluster creation (recommended)
./scripts/create-gke-cluster.sh --gpu

# Or specify options explicitly
./scripts/create-gke-cluster.sh --gpu \
  --project YOUR_PROJECT \
  --zone us-central1-a \
  --cluster-name rhaii-gpu-scaleout-cluster \
  --num-nodes 3
```

**What this does:**
1. Validates accelerator availability in zone
2. Checks node pool prerequisites and quota (3 GPUs)
3. Creates GKE cluster (control plane + standard nodes)
4. Creates GPU T4 node pool with **3 nodes** (n1-standard-4, 1 GPU each)
5. Configures kubectl access

**Success criteria:**
- ✅ Cluster status: RUNNING
- ✅ GPU node pool created with 3 nodes
- ✅ kubectl can list nodes (should see 3 GPU nodes)

**Time:** ~15 minutes (5 min control plane + 10 min 3-node GPU pool)

**Verify node count:**
```bash
kubectl get nodes -l cloud.google.com/gke-accelerator=nvidia-tesla-t4
# Should show 3 nodes
```

---

## Step 3: Install NVIDIA GPU Operator (5 minutes)

**Why needed:** GKE v1.34+ has broken native CDI injection for GPUs. The NVIDIA GPU Operator provides working GPU device injection via CDI specs.

**Install GPU Operator with GKE-specific configuration:**

```bash
# 1. Label GPU nodes to disable GKE's default GPU plugin (conflicts with Operator)
kubectl label nodes -l cloud.google.com/gke-accelerator gke-no-default-nvidia-gpu-device-plugin=true --overwrite

# 2. Add NVIDIA Helm repository (if not already added)
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update

# 3. Install GPU Operator with GKE-specific settings
helm install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --set driver.enabled=false \
  --set hostPaths.driverInstallDir=/home/kubernetes/bin/nvidia \
  --set toolkit.installDir=/home/kubernetes/bin/nvidia \
  --set cdi.enabled=true \
  --set toolkit.env[0].name=RUNTIME_CONFIG_SOURCE \
  --set toolkit.env[0].value=file

# 4. Create ResourceQuota to allow system-critical pods in gpu-operator namespace
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gcp-critical-pods
  namespace: gpu-operator
spec:
  hard:
    pods: "1000"
  scopeSelector:
    matchExpressions:
    - operator: In
      scopeName: PriorityClass
      values:
      - system-node-critical
      - system-cluster-critical
EOF

# 5. Patch GPU Operator deployment to remove priority class (GKE quota conflict)
kubectl patch deployment gpu-operator -n gpu-operator --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/priorityClassName"}]'

# 6. Wait for GPU Operator pods to be ready
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=gpu-operator -n gpu-operator --timeout=300s

# 7. Verify GPU Operator is working
kubectl get pods -n gpu-operator
kubectl exec -n gpu-operator ds/nvidia-container-toolkit-daemonset -- ls /var/run/cdi/
```

**Success criteria:**
- ✅ GPU Operator controller Running
- ✅ nvidia-container-toolkit-daemonset Running on all 3 GPU nodes
- ✅ nvidia-device-plugin-daemonset Running on all 3 GPU nodes
- ✅ CDI specs exist at `/var/run/cdi/` (output from last command shows JSON/YAML files)

**Time:** ~5 minutes

**Configuration notes:**
- `driver.enabled=false` uses GKE's pre-installed NVIDIA drivers (DO NOT let operator install drivers)
- `hostPaths.driverInstallDir=/home/kubernetes/bin/nvidia` points to GKE's writable path (GKE root filesystem is read-only)
- `cdi.enabled=true` generates CDI device specs for GPU injection into containers
- ResourceQuota and priority class patch work around GKE's restrictions on system-critical pods

---

## Namespace Architecture

RHAII uses dedicated namespaces to isolate components:

| Namespace | Purpose | Managed By |
|-----------|---------|------------|
| `rhaii-inference` | Your vLLM workloads, secrets, and NetworkPolicies | You (this guide) |
| `gpu-operator` | NVIDIA GPU Operator (device plugin, CDI toolkit) | NVIDIA GPU Operator |
| `istio-system` | Istio service mesh (istiod) | RHAII operators |
| `opendatahub` | KServe controller, inference gateway, EnvoyFilter | RHAII operators |
| `cert-manager` | TLS certificate management | RHAII operators |
| `openshift-lws-operator` | LeaderWorkerSet controller | RHAII operators |

You only interact with the `rhaii-inference` namespace. Operator namespaces are managed automatically.

---

## Step 4: Create Namespace and Secrets (2 minutes)

Create the workload namespace and deploy secrets.

**Don't have the secret files yet?** Create them from the included templates:
```bash
cp templates/redhat-pull.yaml.template redhat-pull-secret.yaml
cp templates/huggingface-token.yaml.template huggingface-token-secret.yaml
# Edit each file and replace placeholders with your credentials
```
See [Prerequisites — Required Secrets](prerequisites.md#required-secrets) for details.

```bash
# Create workload namespace
kubectl create namespace rhaii-inference

# Set as default namespace for kubectl
kubectl config set-context --current --namespace=rhaii-inference

# Apply Red Hat registry pull secret
kubectl apply -n rhaii-inference -f redhat-pull-secret.yaml

# Apply HuggingFace token secret
kubectl apply -n rhaii-inference -f huggingface-token-secret.yaml

# Verify secrets created
kubectl get secret rhaiis-pull-secret
kubectl get secret huggingface-token
```

**Success criteria:**
- ✅ Both secrets exist in `rhaii-inference` namespace
- ✅ No errors during kubectl apply

---

## Step 5: Install Operators via [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) (10 minutes)

**Follow the installation instructions in the official repository:**

🔗 **https://github.com/opendatahub-io/rhaii-on-xks**

The repository provides automated installation for:
- cert-manager (certificate management)
- Red Hat OpenShift Service Mesh (Istio)
- KServe v0.15 (inference serving)
- LeaderWorkerSet (LWS) controller

**After installation, verify from rhaii-on-xks-gke repository:**
```bash
cd /path/to/rhaii-on-xks-gke
./scripts/verify-deployment.sh --operators-only
```

**Success criteria:**
- ✅ All operator pods Running
- ✅ cert-manager webhook ready
- ✅ Istio control plane ready
- ✅ KServe controller ready

**Time:** ~10 minutes

**Troubleshooting:** See [Operator Installation Guide](operator-installation.md)

---

## Step 6: Deploy Inference Service (10 minutes)

Deploy the 3-replica vLLM inference service with prefix caching:

```bash
# Deploy LLMInferenceService with 3 replicas and prefix caching
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml
```

### Track Deployment Progress

Each pod goes through several stages before it's ready to serve. Use these commands to track progress:

```bash
# Watch overall pod status
kubectl get pods -n rhaii-inference -w
```

**Expected pod lifecycle:**

| Status | What's happening | Duration |
|--------|-----------------|----------|
| `Pending` | Waiting for GPU node to become available | 1-5 min |
| `Init:0/1` | storage-initializer downloading model from HuggingFace | 30-60s |
| `PodInitializing` | Init container finished, main container starting | ~10s |
| `Running` (0/1) | vLLM loading weights + CUDA warmup | 1-3 min |
| `Running` (1/1) | Ready — serving inference requests | ✅ |

### Monitor Each Stage

**Model download (init container):**
```bash
# Check if model download succeeded
kubectl logs <pod-name> -n rhaii-inference -c storage-initializer
# Success: "Successfully copied hf://Qwen/Qwen2.5-3B-Instruct to /mnt/models"
```

**vLLM startup (main container):**
```bash
# Follow vLLM logs in real time
kubectl logs <pod-name> -n rhaii-inference -f

# Key log messages to look for (in order):
#   "Loading safetensors checkpoint shards: 100%"  → model weights loaded
#   "Loading weights took X seconds"               → weights ready
#   "GPU KV cache size: X tokens"                  → KV cache allocated
```

**LLMInferenceService status:**
```bash
kubectl get llminferenceservice -n rhaii-inference -w
# Wait for READY=True
```

### Troubleshooting Stuck Pods

```bash
# Pod stuck in Pending — check for node/resource issues
kubectl describe pod <pod-name> -n rhaii-inference | tail -20

# Pod in Init:CrashLoopBackOff — check storage-initializer logs
kubectl logs <pod-name> -n rhaii-inference -c storage-initializer

# Pod Running but 0/1 Ready — vLLM still loading, check logs
kubectl logs <pod-name> -n rhaii-inference --tail=10
```

### Success Criteria

- ✅ LLMInferenceService READY=True
- ✅ 3 inference pods Running (1/1 Ready, one per GPU node)
- ✅ Gateway has external IP

**Time:** ~10 minutes (pod scheduling + model downloads across 3 nodes)

---

## Step 7: Apply EnvoyFilter and NetworkPolicies (2 minutes)

Apply cache-aware routing and security policies:

### EnvoyFilter for Cache-Aware Routing

```bash
# Apply EnvoyFilter for body forwarding (enables cache-aware routing)
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/envoyfilter-route-extproc-body.yaml
```

**What this does:**
- Enables request body forwarding to EPP scheduler
- Allows EPP to hash request prefixes
- Routes requests with same prefix to same replica for cache hits

### NetworkPolicies for Security

```bash
# Apply all NetworkPolicies
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/networkpolicies/
```

**4 NetworkPolicies applied:**
1. **allow-gateway-to-vllm.yaml** - Allows Istio gateway to reach vLLM pods
2. **allow-epp-scheduler.yaml** - Allows EPP scheduler to communicate with vLLM
3. **allow-istio.yaml** - Allows Istio control plane to manage sidecars
4. **allow-vllm-egress.yaml** - Allows vLLM pods to download models from HuggingFace

**Verify:**
```bash
kubectl get networkpolicies
# Should show 4 policies
```

**Success criteria:**
- ✅ EnvoyFilter applied
- ✅ 4 NetworkPolicies created
- ✅ No errors during apply

---

## Step 8: Verify Deployment (5 minutes)

Verify the deployment is working:

```bash
# Automated verification
./scripts/verify-deployment.sh

# Manual testing
# Get Gateway IP
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')

# Test health endpoint (internal service - use port-forward or test pod)
kubectl run test-curl --image=curlimages/curl:latest --restart=Never -n rhaii-inference --rm -it \
  --command -- curl -k https://qwen-3b-gpu-svc-kserve-workload-svc.rhaii-inference.svc.cluster.local:8000/health

# Test models endpoint to verify service is ready
kubectl run test-curl --image=curlimages/curl:latest --restart=Never -n rhaii-inference --rm -it \
  --command -- curl -k https://qwen-3b-gpu-svc-kserve-workload-svc.rhaii-inference.svc.cluster.local:8000/v1/models

# Test inference endpoint
kubectl run test-curl --image=curlimages/curl:latest --restart=Never -n rhaii-inference --rm -it \
  --command -- curl -k -X POST https://qwen-3b-gpu-svc-kserve-workload-svc.rhaii-inference.svc.cluster.local:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/mnt/models",
    "prompt": "Explain machine learning in one sentence:",
    "max_tokens": 50
  }'
```

**Success criteria:**
- ✅ Health endpoint returns healthy status
- ✅ Models endpoint shows `/mnt/models` available
- ✅ Inference request succeeds
- ✅ Response contains "choices" field with generated text
- ✅ All 3 vLLM replicas healthy

**Check replica status:**
```bash
# Check vLLM workload pods (LLMInferenceService uses different labels)
kubectl get pods -n rhaii-inference -l kserve.io/component=workload
# Should show 3 Running pods

# Check all LLMInferenceService components (workload + router)
kubectl get pods -n rhaii-inference -l app.kubernetes.io/part-of=llminferenceservice
# Should show 4 Running pods (3 vLLM + 1 router/scheduler)
```

**Note:** Gateway external access may require additional firewall configuration. Internal service access (via ClusterIP) works immediately.

---

## Step 9: Performance Validation (5 minutes)

Validate health endpoints, cache-aware routing, and throughput:

```bash
# Run the cache routing test (auto-detects Gateway IP)
./scripts/test-cache-routing.sh

# Or with custom options
./scripts/test-cache-routing.sh --requests 20 --concurrent 10
```

The script tests three things:
1. **Health checks** — verifies `/v1/health`, `/v1/models`, and `/v1/completions` endpoints
2. **Cache routing** — sends repeated requests with identical prefix, measures latency improvement
3. **Throughput** — fires parallel requests and reports req/s and latency percentiles

**Expected behavior (GPU):**
- First request: ~250ms (cache miss)
- Subsequent requests: <150ms (cache hit on same replica)
- Throughput: ~18 req/s (parallel)
- P50 latency: <300ms

---

## 🎉 Success!

Your RHAII GPU deployment is ready for production traffic!

### Quick Reference

**Inference Endpoint:**
```
http://$GATEWAY_IP/v1/completions
```

**OpenAI-Compatible API:**
- POST `/v1/completions` - Text completion
- POST `/v1/chat/completions` - Chat completion
- GET `/v1/models` - List available models
- GET `/v1/health` - Health check

**Monitor Deployment:**
```bash
# Check all 3 replicas
kubectl get pods -l serving.kserve.io/inferenceservice

# View logs for specific replica
kubectl logs <pod-name> -f

# Check GPU usage across nodes
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
```

---

## Operational Procedures

### Scale Up/Down Replicas

**Add more replicas (requires additional nodes):**

```yaml
# Edit manifest
spec:
  replicas: 5  # Scale to 5 replicas
```

Apply changes:
```bash
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml

# Scale node pool to match
gcloud container clusters resize rhaii-gpu-scaleout-cluster \
  --node-pool gpu-pool \
  --num-nodes 5 \
  --zone us-central1-a
```

**Requirements:**
- 5 replicas = 5 GPUs

**Scale down:**
```yaml
spec:
  replicas: 2  # Scale to 2 replicas
```

```bash
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml

# Scale node pool
gcloud container clusters resize rhaii-gpu-scaleout-cluster \
  --node-pool gpu-pool \
  --num-nodes 2 \
  --zone us-central1-a
```

### Rolling Updates

**Update vLLM version:**
```yaml
spec:
  template:
    containers:
    - image: registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.1.0  # New version
```

```bash
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml
```

KServe performs rolling updates automatically, maintaining availability:
- Updates 1 replica at a time
- Waits for new replica to be Ready
- Continues to next replica
- Zero downtime during update

---

## Scale to Zero

```bash
# Scale node pool to zero
gcloud container clusters resize rhaii-gpu-scaleout-cluster \
  --node-pool gpu-pool \
  --num-nodes 0 \
  --zone us-central1-a
```

### Scale Back Up

```bash
# Restore 3-node pool
gcloud container clusters resize rhaii-gpu-scaleout-cluster \
  --node-pool gpu-pool \
  --num-nodes 3 \
  --zone us-central1-a

# Wait for nodes ready (~5 minutes)
kubectl get nodes -w
```

---

## Troubleshooting

### Only 1/3 or 2/3 Replicas Starting

**Symptoms:**
- LLMInferenceService shows READY=False
- Only 1 or 2 pods Running

**Causes:**
- Insufficient GPU quota (need 3 GPUs)
- Node pool only has 1 or 2 nodes

**Solution:**
```bash
# Check GPU quota
gcloud compute project-info describe --project=YOUR_PROJECT | grep -i nvidia

# Check node count
kubectl get nodes -l cloud.google.com/gke-accelerator=nvidia-tesla-t4

# If nodes < 3, scale node pool
gcloud container clusters resize rhaii-gpu-scaleout-cluster \
  --node-pool gpu-pool \
  --num-nodes 3 \
  --zone us-central1-a

# Check events for quota errors
kubectl get events --sort-by='.lastTimestamp' | grep -i quota
```

### GPU Not Detected in Pods

**Symptoms:**
- vLLM fails to start
- Logs show "No GPU detected"

**Causes:**
- GPU not allocated to pod
- NVIDIA drivers not installed

**Solution:**
```bash
# Verify GPU allocation on nodes
kubectl describe nodes | grep -A 5 "Allocated resources" | grep nvidia

# Check pod resource requests
kubectl describe pod <vllm-pod> | grep -A 5 "Limits"

# DO NOT install GPU Operator (GKE provides native GPU support)
```

### Cache Routing Not Working

**Symptoms:**
- All requests have similar latency (~250ms)
- No cache hit latency improvement (<150ms)

**Causes:**
- EnvoyFilter not applied
- Request prefixes not consistent
- EPP scheduler not enabled

**Solution:**
```bash
# Verify EnvoyFilter applied
kubectl get envoyfilter -n istio-system

# If missing, apply
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/envoyfilter-route-extproc-body.yaml

# Test with identical prompts
for i in {1..5}; do
  curl -s -w "\nTime: %{time_total}s\n" -X POST http://$GATEWAY_IP/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "Qwen/Qwen2.5-3B-Instruct", "prompt": "SAME PREFIX HERE", "max_tokens": 10}'
done
# Should show decreasing latency after first request
```

### NetworkPolicy Blocking Traffic

**Symptoms:**
- Inference requests fail with connection refused
- Gateway returns 503 errors

**Causes:**
- NetworkPolicies too restrictive
- Missing NetworkPolicy for new component

**Solution:**
```bash
# Verify all 4 NetworkPolicies applied
kubectl get networkpolicies
# Should show: allow-gateway-to-vllm, allow-epp-scheduler, allow-istio, allow-vllm-egress

# If missing, reapply
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/networkpolicies/

# Check pod connectivity
kubectl exec -it <vllm-pod> -- curl -s http://localhost:8000/health
```

### High Latency Despite Caching

**Symptoms:**
- P50 latency >600ms (expected <300ms)
- Cache hit rate low

**Causes:**
- Request prefixes vary too much
- GPU memory exhausted
- Network congestion

**Solution:**
```bash
# Check GPU memory usage
kubectl exec -it <vllm-pod> -- nvidia-smi

# Check pod resource usage
kubectl top pods -l serving.kserve.io/inferenceservice

# Analyze request patterns
kubectl logs -l serving.kserve.io/inferenceservice | grep "prompt"

# For debugging, enable vLLM request logging (removes --disable-log-requests)
# Edit manifest, remove --disable-log-requests flag
```

**See [Troubleshooting Guide](troubleshooting.md) for more solutions.**

---

## Reference

**Manifests:**
- `deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml`
- `deployments/istio-kserve/caching-pattern/manifests/envoyfilter-route-extproc-body.yaml`
- `deployments/istio-kserve/caching-pattern/manifests/networkpolicies/`

**Performance:** ~18 req/s parallel, ~4.8 req/s serial, <300ms P50 latency

**Recommended zones:**
- `us-central1-a`, `europe-west4-a` (primary)
- Wide availability in `us-*` and `europe-*` regions (20+ zones)

---

**Need help?** Check [Troubleshooting](troubleshooting.md)
