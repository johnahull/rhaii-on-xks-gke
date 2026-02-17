# High-Throughput Scale-Out Deployment (GPU)

Deploy 3-replica vLLM service with prefix caching for production workloads on GPU T4.

## Overview

**What you'll deploy:**
- GKE cluster with GPU T4 node pool (3 GPUs total)
- RHAII operators (cert-manager, Istio, KServe, LWS)
- 3-replica vLLM inference service with prefix caching enabled
- Cache-aware routing via EnvoyFilter and EPP scheduler
- Security isolation via NetworkPolicies

**Performance:**
- ~18 req/s parallel requests (vs 5-6 req/s single-model)
- ~4.8 req/s serial requests (vs 1.5 req/s single-model)
- 3.2× throughput improvement over baseline

**Cost:**
- Running: ~$228/day ($6,840/month)
- vs Single-model: 2.85× cost for 3.2× throughput
- **Cost efficiency: 1.12× better cost-per-request**
- Scaled to zero: ~$6/day (cluster overhead only)

**Time:** ~45 minutes total

---

## When to Choose This Deployment

**Choose GPU Scale-Out Deployment if:**
- Production workload with >10 req/s expected traffic
- Shared prompts/prefixes across requests (translation, summarization, Q&A)
- Budget allows ~$228/day ($6,840/month)
- Need 3.2× throughput improvement over baseline
- Cost efficiency matters (1.12× better cost-per-request with caching)
- Wide zone availability required (T4 available in 20+ zones)
- Lower cost alternative to TPU scale-out ($228/day vs $377/day)

**Choose Baseline GPU Deployment instead if:**
- Development, testing, or PoC workloads
- <10 req/s traffic expected
- Budget-constrained (~$80/day for single-model GPU)
- Unique prompts without prefix sharing
- Want to start small and scale later

**Choose TPU Scale-Out if:**
- Maximum performance required (~25 req/s vs ~18 req/s)
- Budget allows higher cost ($377/day vs $228/day)
- Zone constraints acceptable (TPU available in 5 zones)

**See:** [30-Minute GPU Quickstart](quickstart-gpu.md) for baseline deployment

---

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Google Cloud account with billing enabled
- [ ] Project: `YOUR_PROJECT` (or your project) with Owner/Editor role
- [ ] `gcloud` CLI installed and authenticated
- [ ] `kubectl` CLI installed
- [ ] Red Hat registry credentials in `redhat-pull-secret.yaml`
- [ ] HuggingFace token for model access
- [ ] **GPU T4 quota: 3 GPUs minimum**
- [ ] **Budget approved: ~$228/day** ($6,840/month)
- [ ] Workload analysis confirms shared prompts benefit from caching

**Need help?** See [Prerequisites Guide](prerequisites.md) for detailed setup instructions.

---

## Architecture

This scale-out deployment provides high-throughput inference with intelligent request routing.

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
- HTTP vLLM endpoints (Istio provides mTLS encryption)

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

### GPU vs TPU Comparison

| Metric | GPU T4 Scale-Out | TPU v6e Scale-Out |
|--------|------------------|-------------------|
| **Throughput** | ~18 req/s | ~25 req/s |
| **Cost** | $228/day | $377/day |
| **Memory** | 13.12 GiB/GPU | 16 GiB/chip |
| **Zone Availability** | 20+ zones | 5 zones |
| **Best For** | Cost-conscious production | Maximum performance |

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
./scripts/preflight-check.sh --deployment istio-kserve/caching-pattern --accelerator gpu
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
  --deployment istio-kserve/caching-pattern \
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

**Note:** GKE automatically installs NVIDIA drivers. DO NOT install GPU Operator.

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

## Step 5: Deploy Scale-Out Configuration (10 minutes)

Deploy the 3-replica vLLM inference service with prefix caching:

```bash
# Deploy LLMInferenceService with 3 replicas and prefix caching
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml

# Monitor deployment
kubectl get llminferenceservice -w
```

**Expected output:**
```
NAME                READY   URL
gemma-2b-gpu-svc    True    http://...
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
          --max-model-len=4096 \
          ...
    resources:
      limits:
        nvidia.com/gpu: "1"  # 1 GPU per replica
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
- ✅ 3 inference pods running (1 per GPU node)
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

Verify the scale-out deployment is working:

```bash
# Automated verification
./scripts/verify-deployment.sh --deployment scale-out

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
      "prompt": "Translate to Spanish: Good morning",
      "max_tokens": 10
    }' | jq -r '.choices[0].text'
done
```

**Expected behavior:**
- First request: ~250ms (cache miss)
- Subsequent requests: <150ms (cache hit on same replica)

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
- Throughput: ~18 req/s (parallel)
- P50 latency: <300ms
- P99 latency: <600ms
- Cache hit rate: >70% (for workloads with shared prefixes)

**Success criteria:**
- ✅ Throughput >15 req/s
- ✅ Cache routing working (consistent low latency for same prefix)
- ✅ No errors or failures during benchmark

---

## 🎉 Success!

Your RHAII GPU scale-out deployment is ready for production traffic!

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
- Budget: ~$380/day

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

## Cost Management

### Scale to Zero When Not in Use

```bash
# Scale node pool to zero (saves ~$222/day)
gcloud container clusters resize rhaii-gpu-scaleout-cluster \
  --node-pool gpu-pool \
  --num-nodes 0 \
  --zone us-central1-a

# Cost when scaled to zero: ~$6/day (cluster overhead)
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

### Scheduled Scaling

For automated cost savings, see [Cost Management Guide](cost-management.md) for:
- GCP Cloud Scheduler integration
- Business hours scaling
- Budget alerts

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

## Appendix: Migration from Baseline

If you already have a single-model baseline GPU deployment and want to migrate to scale-out:

### Migration Steps

1. **Request additional GPU quota** (3 GPUs total vs 1 GPU baseline)
2. **Budget approval** for increased cost (~$228/day vs ~$80/day)
3. **Delete baseline deployment:**
   ```bash
   kubectl delete llminferenceservice gemma-2b-gpu-svc
   # Wait for resources released
   kubectl get pods -w
   ```
4. **Scale node pool to 3 nodes:**
   ```bash
   gcloud container clusters resize rhaii-cluster \
     --node-pool gpu-pool \
     --num-nodes 3 \
     --zone us-central1-a
   # Wait ~5 minutes for nodes ready
   kubectl get nodes -w
   ```
5. **Deploy scale-out configuration** (follow Steps 5-8 above)

### Rollback Procedure

To revert to baseline single-model deployment:

```bash
# 1. Delete scale-out deployment
kubectl delete llminferenceservice gemma-2b-gpu-svc

# 2. Scale node pool to 1
gcloud container clusters resize rhaii-cluster \
  --node-pool gpu-pool \
  --num-nodes 1 \
  --zone us-central1-a

# 3. Redeploy baseline configuration
kubectl apply -f deployments/istio-kserve/baseline-pattern/manifests/llmisvc-gpu.yaml
```

### Comparison: Baseline vs Scale-Out

| Metric | Baseline | Scale-Out | Improvement |
|--------|----------|-----------|-------------|
| **Replicas** | 1 | 3 | 3× |
| **GPUs** | 1 | 3 | 3× |
| **Throughput (parallel)** | 5-6 req/s | 18 req/s | 3.2× |
| **Throughput (serial)** | 1.5 req/s | 4.8 req/s | 3.2× |
| **Cost** | $80/day | $228/day | 2.85× |
| **Cost-per-request** | Baseline | 1.12× better | 12% savings |
| **Prefix caching** | No | Yes | ~70% latency ↓ |

---

## Next Steps

### Production Hardening

Prepare for production:

**[Production Hardening Guide](production-hardening.md)**
- mTLS STRICT mode
- Resource limits and HPA
- Monitoring and alerting
- SLO/SLA configuration

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

### Upgrade to TPU

**For maximum performance:**
- See [Scale-Out Deployment (TPU)](scale-out-deployment-tpu.md)
- ~25 req/s throughput vs ~18 req/s GPU
- Higher cost: $377/day vs $228/day
- Limited zone availability

---

## Reference

**Manifests:**
- `deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml`
- `deployments/istio-kserve/caching-pattern/manifests/envoyfilter-route-extproc-body.yaml`
- `deployments/istio-kserve/caching-pattern/manifests/networkpolicies/`

**Cost:** ~$228/day ($6,840/month) running, ~$6/day scaled to zero

**Performance:** ~18 req/s parallel, ~4.8 req/s serial, <300ms P50 latency

**Recommended zones:**
- `us-central1-a`, `europe-west4-a` (primary)
- Wide availability in `us-*` and `europe-*` regions (20+ zones)

---

**Need help?** Check [FAQ](faq.md) or [Troubleshooting](troubleshooting.md)
