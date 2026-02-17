# RHAII Deployment Guide (TPU)

Deploy a production vLLM inference service on TPU v6e with prefix caching and intelligent routing.

## Overview

**What you'll deploy:**
- GKE cluster with 3-node TPU v6e pool (12 TPU chips total)
- RHAII operators (cert-manager, Istio, KServe, LWS)
- 3-replica vLLM inference service with prefix caching enabled
- Cache-aware routing via EnvoyFilter and EPP scheduler
- Security isolation via NetworkPolicies

**Performance:**
- ~25 req/s parallel requests
- ~6.3 req/s serial requests

**Time:** ~50 minutes total

---

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Google Cloud account with billing enabled
- [ ] Project: `YOUR_PROJECT` (or your project) with Owner/Editor role
- [ ] `gcloud` CLI installed and authenticated
- [ ] `kubectl` CLI installed
- [ ] Red Hat registry credentials in `redhat-pull-secret.yaml`
- [ ] HuggingFace token for model access
- [ ] **TPU v6e quota: 12 chips minimum** (3 nodes × 4 chips)

**Need help?** See [Prerequisites Guide](prerequisites.md) for detailed setup instructions.

---

## Architecture

This deployment provides high-throughput inference with intelligent request routing.

### Components

**3 vLLM Replicas:**
- Each replica runs on dedicated TPU node (4 chips per node)
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
Client Request: "Translate to French: Hello"
    ↓
Istio Gateway (external IP)
    ↓
EnvoyFilter (hash request prefix)
    ↓
EPP Scheduler (select replica based on hash)
    ↓
Replica 2 (has cached "Translate to French:" prefix)
    ↓
Fast response (~50ms vs ~200ms without cache)
```

### Cache Benefits

**With Prefix Caching:**
- Repeated prefixes cached in KV cache
- ~75% latency reduction on cache hits
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
./scripts/preflight-check.sh --accelerator tpu
# Instead of: ./scripts/preflight-check.sh ... --project YOUR_PROJECT --zone europe-west4-a
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
  --accelerator tpu \
  --zone europe-west4-a \
  --customer
```

**Success criteria:**
- ✅ All tools installed (gcloud, kubectl, jq)
- ✅ GCP authentication valid
- ✅ Required permissions granted
- ✅ Secrets exist (pull-secret, huggingface-token)
- ✅ TPU v6e quota: 12 chips available

**If checks fail:** See troubleshooting output for specific fixes.

---

## Step 2: Create GKE Cluster with 3-Node TPU Pool (20 minutes)

Create a production-ready GKE cluster with 3-node TPU v6e pool:

```bash
# Interactive cluster creation (recommended)
./scripts/create-gke-cluster.sh --tpu

# Or specify options explicitly with 3 nodes
./scripts/create-gke-cluster.sh --tpu \
  --project YOUR_PROJECT \
  --zone europe-west4-a \
  --cluster-name rhaii-tpu-scaleout-cluster \
  --num-nodes 3
```

**What this does:**
1. Validates accelerator availability in zone
2. Checks node pool prerequisites and quota (12 chips)
3. Creates GKE cluster (control plane + standard nodes)
4. Creates TPU v6e node pool with **3 nodes** (ct6e-standard-4t, 4 chips each)
5. Configures kubectl access

**Success criteria:**
- ✅ Cluster status: RUNNING
- ✅ TPU node pool created with 3 nodes
- ✅ kubectl can list nodes (should see 3 TPU nodes)

**Time:** ~20 minutes (5 min control plane + 15 min 3-node TPU pool)

**Verify node count:**
```bash
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice
# Should show 3 nodes
```

---

## Step 3: Install Operators via [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) (10 minutes)

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

## Step 4: Create Secrets (2 minutes)

Deploy the required secrets for model access:

```bash
# Apply Red Hat registry pull secret
kubectl apply -f redhat-pull-secret.yaml

# Apply HuggingFace token secret
kubectl apply -f huggingface-token-secret.yaml

# Verify secrets created
kubectl get secret rhaiis-pull-secret
kubectl get secret huggingface-token
```

**Success criteria:**
- ✅ Both secrets exist in default namespace
- ✅ No errors during kubectl apply

---

## Step 5: Deploy Inference Service (10 minutes)

Deploy the 3-replica vLLM inference service with prefix caching:

```bash
# Deploy LLMInferenceService with 3 replicas and prefix caching
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml

# Monitor deployment
kubectl get llminferenceservice -w
```

**Expected output:**
```
NAME                READY   URL
gemma-2b-tpu-svc    True    http://...
```

**Wait for READY=True** (may take 10-15 minutes for 3 pods + model downloads)

**Key configuration in manifest:**
```yaml
spec:
  replicas: 3  # 3 replicas for high throughput
  router:
    route: {}      # Auto-create HTTPRoute
    gateway: {}    # Bind to Gateway
    scheduler: {}  # Enable EPP scheduler
  template:
    containers:
    - args:
      - |
        python3 -m vllm.entrypoints.openai.api_server \
          --enable-prefix-caching \  # Enable prefix caching
          --tensor-parallel-size=4 \
          ...
```

**Monitor pod creation:**
```bash
# Watch all 3 pods come up
kubectl get pods -l serving.kserve.io/inferenceservice -w

# Check logs for first pod
kubectl logs -l serving.kserve.io/inferenceservice --tail=50
```

**Success criteria:**
- ✅ LLMInferenceService READY=True
- ✅ 3 inference pods running (1 per TPU node)
- ✅ Gateway has external IP

**Time:** ~10 minutes (pod scheduling + model downloads across 3 nodes)

---

## Step 6: Apply EnvoyFilter and NetworkPolicies (2 minutes)

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

## Step 7: Verify Deployment (5 minutes)

Verify the deployment is working:

```bash
# Automated verification
./scripts/verify-deployment.sh

# Manual testing
# Get Gateway IP
export GATEWAY_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test health endpoint
curl http://$GATEWAY_IP/v1/health

# Test inference endpoint
curl -X POST http://$GATEWAY_IP/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-2b-it",
    "prompt": "Explain machine learning in one sentence:",
    "max_tokens": 50
  }'
```

**Success criteria:**
- ✅ Health endpoint returns 200
- ✅ Inference request succeeds
- ✅ Response contains "choices" field
- ✅ All 3 replicas healthy

**Check replica status:**
```bash
kubectl get pods -l serving.kserve.io/inferenceservice
# Should show 3 Running pods
```

---

## Step 8: Performance Validation (5 minutes)

Validate cache-aware routing and throughput:

### Test Cache Routing

```bash
# Send 10 requests with identical prefix
for i in {1..10}; do
  curl -s -w "\nTime: %{time_total}s\n" -X POST http://$GATEWAY_IP/v1/completions \
    -H "Content-Type: application/json" \
    -d '{
      "model": "google/gemma-2b-it",
      "prompt": "Translate to French: Hello world",
      "max_tokens": 10
    }' | jq -r '.choices[0].text'
done
```

**Expected behavior:**
- First request: ~200ms (cache miss, XLA compilation)
- Subsequent requests: <100ms (cache hit on same replica)

### Load Testing

```bash
# Run benchmark with concurrent requests
cd /path/to/rhaii-on-xks-gke
python3 benchmarks/python/benchmark_vllm.py \
  --endpoint http://$GATEWAY_IP/v1/completions \
  --model google/gemma-2b-it \
  --concurrent 10 \
  --duration 60
```

**Expected results:**
- Throughput: ~25 req/s (parallel)
- P50 latency: <200ms
- P99 latency: <500ms
- Cache hit rate: >70% (for workloads with shared prefixes)

**Success criteria:**
- ✅ Throughput >20 req/s
- ✅ Cache routing working (consistent low latency for same prefix)
- ✅ No errors or failures during benchmark

---

## 🎉 Success!

Your RHAII TPU deployment is ready for production traffic!

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

# Check resource usage across nodes
kubectl top nodes
kubectl top pods -l serving.kserve.io/inferenceservice
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
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml

# Scale node pool to match
gcloud container clusters resize rhaii-tpu-scaleout-cluster \
  --node-pool tpu-pool \
  --num-nodes 5 \
  --zone europe-west4-a
```

**Requirements:**
- 5 replicas = 20 TPU chips (5 nodes × 4 chips)

**Scale down:**
```yaml
spec:
  replicas: 2  # Scale to 2 replicas
```

```bash
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml

# Scale node pool
gcloud container clusters resize rhaii-tpu-scaleout-cluster \
  --node-pool tpu-pool \
  --num-nodes 2 \
  --zone europe-west4-a
```

### Rolling Updates

**Update vLLM version:**
```yaml
spec:
  template:
    containers:
    - image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.3.0  # New version
```

```bash
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml
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
gcloud container clusters resize rhaii-tpu-scaleout-cluster \
  --node-pool tpu-pool \
  --num-nodes 0 \
  --zone europe-west4-a
```

### Scale Back Up

```bash
# Restore 3-node pool
gcloud container clusters resize rhaii-tpu-scaleout-cluster \
  --node-pool tpu-pool \
  --num-nodes 3 \
  --zone europe-west4-a

# Wait for nodes ready (~10 minutes)
kubectl get nodes -w
```

---

## Troubleshooting

### Only 1/3 or 2/3 Replicas Starting

**Symptoms:**
- LLMInferenceService shows READY=False
- Only 1 or 2 pods Running

**Causes:**
- Insufficient TPU quota (need 12 chips)
- Node pool only has 1 or 2 nodes

**Solution:**
```bash
# Check TPU quota
gcloud compute project-info describe --project=YOUR_PROJECT | grep -i tpu

# Check node count
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice

# If nodes < 3, scale node pool
gcloud container clusters resize rhaii-tpu-scaleout-cluster \
  --node-pool tpu-pool \
  --num-nodes 3 \
  --zone europe-west4-a

# Check events for quota errors
kubectl get events --sort-by='.lastTimestamp' | grep -i quota
```

### Cache Routing Not Working

**Symptoms:**
- All requests have similar latency (~200ms)
- No cache hit latency improvement (<100ms)

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
    -d '{"model": "google/gemma-2b-it", "prompt": "SAME PREFIX HERE", "max_tokens": 10}'
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
- P50 latency >500ms (expected <200ms)
- Cache hit rate low

**Causes:**
- Request prefixes vary too much
- Model loaded on cold replica
- Network congestion

**Solution:**
```bash
# Check pod resource usage
kubectl top pods -l serving.kserve.io/inferenceservice

# Analyze request patterns
kubectl logs -l serving.kserve.io/inferenceservice | grep "prompt"

# For debugging, enable vLLM request logging (removes --disable-log-requests)
# Edit manifest, remove --disable-log-requests flag
```

**See [Troubleshooting Guide](troubleshooting.md) for more solutions.**

---

## Next Steps

### Advanced Features

**Multi-Model Serving:**
- Deploy multiple models (Gemma 2B + Llama 3 8B)
- Model routing based on request headers
- See [Multi-Model Setup Guide](multi-model-updates.md)

### Monitoring & Observability

**Set up comprehensive monitoring:**
- Prometheus metrics collection
- Grafana dashboards
- Alerting rules for SLA violations
- See [Monitoring Guide](monitoring.md)

---

## Reference

**Manifests:**
- `deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml`
- `deployments/istio-kserve/caching-pattern/manifests/envoyfilter-route-extproc-body.yaml`
- `deployments/istio-kserve/caching-pattern/manifests/networkpolicies/`

**Performance:** ~25 req/s parallel, ~6.3 req/s serial, <200ms P50 latency

**Recommended zones:**
- `europe-west4-a` (primary - most reliable TPU availability)
- `us-south1-a`, `us-east5-a`, `us-central1-b` (alternatives)

---

**Need help?** Check [FAQ](faq.md) or [Troubleshooting](troubleshooting.md)
