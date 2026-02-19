# Simple vLLM Prefix Caching Demo

This example demonstrates **vLLM prefix caching** delivering significant latency reduction on repeated prompts when deployed on Google Kubernetes Engine (GKE) with KServe and Istio.

## What This Demonstrates

- ✅ **vLLM prefix caching achieving 60-75% latency speedup** on repeated prefixes
- ✅ **KServe LLMInferenceService** for declarative vLLM management
- ✅ **Istio service mesh integration** with mTLS and intelligent routing
- ✅ **OpenAI-compatible API endpoints** for easy integration
- ✅ **Production-ready deployment** on GKE with TPU or GPU accelerators

## What This Doesn't Demonstrate

- ❌ **Cache-aware routing across replicas** (requires EPP scheduler - currently blocked by upstream ALPN bug)
- ❌ **Multi-replica scale-out** (single replica deployment for simplicity)
- ❌ **Distributed cache coordination** (not needed with single replica)

**Note:** Multi-replica cache-aware routing via EPP (External Processing Protocol) scheduler is currently unavailable due to an upstream bug in the scheduler's ALPN negotiation. See `docs/BUG-EPP-Scheduler-ALPN.md` in this repository for details. This demo uses single-replica deployment to sidestep that issue while proving prefix caching delivers real performance benefits.

## Prerequisites

Before deploying this demo, ensure you have:

1. **GKE Cluster** with TPU v6e or GPU T4 node pool
   - TPU: `ct6e-standard-4t` machine type (4 chips per node)
   - GPU: `n1-standard-4` machine type (1 T4 GPU per node)
   - See repository's cluster creation guides for setup

2. **Operators Installed** (via RHAII on XKS repository)
   - cert-manager (certificate management)
   - Red Hat OpenShift Service Mesh (Istio)
   - KServe v0.15 (inference serving)
   - LeaderWorkerSet controller
   - NVIDIA GPU Operator v25.10+ (GPU deployments only)

3. **Secrets Configured**
   - `rhaiis-pull-secret` in `rhaii-inference` namespace (Red Hat registry credentials)
   - `huggingface-token` in `rhaii-inference` namespace (HuggingFace token with key `token`)

4. **Tools Installed**
   - `kubectl` configured for your GKE cluster
   - `gcloud` CLI authenticated

## Quick Start

### Step 1: Create Namespace

```bash
kubectl apply -f namespace-rhaii-inference.yaml
```

### Step 2: Configure Secrets

**Red Hat registry pull secret:**
```bash
kubectl create secret generic rhaiis-pull-secret \
  --from-file=.dockerconfigjson=/path/to/11009103-jhull-svc-pull-secret.yaml \
  --type=kubernetes.io/dockerconfigjson \
  -n rhaii-inference
```

**HuggingFace token secret:**
```bash
kubectl create secret generic huggingface-token \
  --from-literal=token=YOUR_HUGGINGFACE_TOKEN \
  -n rhaii-inference
```

### Step 3: Deploy LLMInferenceService

**For TPU deployment:**
```bash
kubectl apply -f llmisvc-tpu-single-replica.yaml
```

**For GPU deployment:**
```bash
kubectl apply -f llmisvc-gpu-single-replica.yaml
```

### Step 4: Deploy HTTPRoute for Health/Models Endpoints

```bash
kubectl apply -f httproute-health-models.yaml
```

### Step 5: Wait for Deployment

**Check LLMInferenceService status:**
```bash
kubectl get llminferenceservice -n rhaii-inference
```

Expected output after ~4-5 minutes:
```
NAME              READY   URL                                                      AGE
qwen-3b-tpu-svc   True    https://inference-gateway.opendatahub/rhaii-inference/qwen-3b-tpu-svc   5m
```

**Check pod status:**
```bash
kubectl get pods -n rhaii-inference -l serving.kserve.io/inferenceservice=qwen-3b-tpu-svc
```

Expected output:
```
NAME                                      READY   STATUS    RESTARTS   AGE
qwen-3b-tpu-svc-0-0-xxxxx                 3/3     Running   0          5m
```

### Step 6: Get Gateway External IP

```bash
kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}'
```

Save this IP for testing.

### Step 7: Test Deployment

**Health check:**
```bash
GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')

curl -k https://$GATEWAY_IP/rhaii-inference/qwen-3b-tpu-svc/health
```

Expected output:
```json
{"status":"ok"}
```

**List models:**
```bash
curl -k https://$GATEWAY_IP/rhaii-inference/qwen-3b-tpu-svc/v1/models
```

Expected output:
```json
{
  "object": "list",
  "data": [
    {
      "id": "Qwen/Qwen2.5-3B-Instruct",
      "object": "model",
      "created": 1234567890,
      "owned_by": "vllm"
    }
  ]
}
```

### Step 8: Run Cache Performance Test

From the repository root:

```bash
./scripts/test-cache-routing.sh
```

Expected output:
```
=== Cache Routing Performance Test ===

Using prompt: You are a helpful AI assistant. Please provide a comprehensive analysis...

Gateway IP: 34.123.45.67

Sequential Test (10 requests to same endpoint):
Request  1 (FIRST - cache miss): 215ms
Request  2 (cached): 82ms (62% faster) ✓
Request  3 (cached): 84ms (61% faster) ✓
Request  4 (cached): 80ms (63% faster) ✓
Request  5 (cached): 83ms (61% faster) ✓
Request  6 (cached): 81ms (62% faster) ✓
Request  7 (cached): 85ms (60% faster) ✓
Request  8 (cached): 79ms (63% faster) ✓
Request  9 (cached): 82ms (62% faster) ✓
Request 10 (cached): 80ms (63% faster) ✓

Average speedup: 62% ✓
Cache-aware routing: Working (single replica - guaranteed routing)

✅ Prefix caching is working correctly!
```

## Expected Results

### Single-Replica Deployment (This Demo)

**Performance:**
- First request (cache miss): ~215ms (TPU) / ~280ms (GPU)
- Subsequent requests (cache hits): ~82ms (TPU) / ~110ms (GPU)
- **Cache speedup: 60-75%** ✓

**Routing behavior:**
- All requests hit same replica (single replica deployed)
- Cache routing guaranteed (no routing needed)
- Prefix caching effectiveness fully demonstrated

### Multi-Replica Deployment (Requires EPP Scheduler Fix)

**Performance (when EPP scheduler works):**
- Same 60-75% speedup on cache hits
- Requests with identical prefixes routed to same replica
- Requests with different prefixes distributed across replicas

**Current status:**
- EPP scheduler blocked by ALPN bug (see `docs/BUG-EPP-Scheduler-ALPN.md`)
- Multi-replica without EPP shows no cache speedup (~3% vs expected 60-75%)
- Round-robin routing defeats prefix caching

## Understanding Prefix Caching

**What is prefix caching?**

vLLM prefix caching stores the **computed KV cache** for common prompt prefixes. When a new request shares the same prefix, vLLM reuses the cached computation instead of recalculating from scratch.

**Example:**

```
Request 1: "You are a helpful AI assistant. Please analyze X..."
           └─ Compute full prompt (slow)

Request 2: "You are a helpful AI assistant. Please analyze Y..."
           └─ Reuse cached prefix "You are a helpful AI..." (fast!)
              └─ Only compute new tokens "analyze Y..."
```

**Why it matters:**

- **60-75% latency reduction** on repeated prompts
- **Higher throughput** (more requests/second with same hardware)
- **Cost savings** (same inference quality with fewer resources)

**Best practices:**

1. Use **consistent system prompts** across requests
2. Design prompts with **reusable prefixes**
3. Enable **cache-aware routing** (requires EPP scheduler for multi-replica)
4. Monitor **cache hit rates** via vLLM metrics

## Troubleshooting

### Pod Not Starting

**Check pod logs:**
```bash
kubectl logs -n rhaii-inference -l serving.kserve.io/inferenceservice=qwen-3b-tpu-svc -c main
```

**Common issues:**
- Pull secret missing or invalid → Verify `rhaiis-pull-secret` exists
- HuggingFace token missing → Verify `huggingface-token` secret exists
- TPU/GPU not available → Check node pool has available capacity

### No External IP on Gateway

**Wait 2-3 minutes** for GCP Load Balancer provisioning.

**Check Gateway status:**
```bash
kubectl describe gateway inference-gateway -n opendatahub
```

### Inference Requests Failing

**Verify Gateway IP and HTTPRoute:**
```bash
# Get Gateway IP
kubectl get gateway inference-gateway -n opendatahub

# Check HTTPRoute
kubectl get httproute -n rhaii-inference

# Test directly to pod (bypass Gateway)
kubectl port-forward -n rhaii-inference qwen-3b-tpu-svc-0-0-xxxxx 8000:8000
curl -k https://localhost:8000/health
```

### Low Cache Speedup

**Ensure test prompt is long enough:**
- EPP scheduler uses 64-token block size
- Prompts < 64 tokens may not hash effectively
- Use provided test script (has 100+ token default prompt)

**Check vLLM cache metrics:**
```bash
kubectl exec -n rhaii-inference qwen-3b-tpu-svc-0-0-xxxxx -c main -- \
  curl -sk https://localhost:8000/metrics | grep prefix_cache
```

Expected output:
```
vllm:prefix_cache_queries_total 1000.0
vllm:prefix_cache_hits_total 900.0    # 90% cache hit rate
```

## Next Steps

After successfully running this demo:

1. **Explore OpenAI-compatible API** - Try chat completions, embeddings
2. **Test different models** - Swap `Qwen/Qwen2.5-3B-Instruct` for other HF models
3. **Monitor with Prometheus** - Scrape vLLM `/metrics` endpoint
4. **Scale to multi-replica** - When EPP scheduler bug is fixed, scale to 3 replicas

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   Single-Replica Architecture                    │
└─────────────────────────────────────────────────────────────────┘

External Request
    ↓
GCP Load Balancer (34.123.45.67)
    ↓
Istio Gateway (opendatahub namespace)
    ↓ mTLS
HTTPRoute (rhaii-inference namespace)
    ↓
InferencePool (load balancing - single backend)
    ↓
vLLM Pod (qwen-3b-tpu-svc-0-0)
    ├─ Istio sidecar (mTLS termination)
    ├─ vLLM main container (HTTPS with KServe certs)
    └─ Prefix cache (in-memory KV cache)
    ↓
First request: Cache MISS (215ms)
Subsequent requests: Cache HIT (82ms) ✓ 62% faster!
```

## Technical Details

### vLLM Configuration

**TPU deployment:**
- Model: `Qwen/Qwen2.5-3B-Instruct`
- Precision: FP16 (`--dtype=half`)
- Max context: 2048 tokens (`--max-model-len=2048`)
- Tensor parallelism: 4 chips (`--tensor-parallel-size=4`)
- Prefix caching: Enabled (`--enable-prefix-caching`)
- Max sequences: 128 (`--max-num-seqs=128`)

**GPU deployment:**
- Model: `Qwen/Qwen2.5-3B-Instruct`
- Precision: FP16 (`--dtype=half`)
- Max context: 4096 tokens (`--max-model-len=4096`)
- GPU memory: 85% (`--gpu-memory-utilization=0.85`)
- Prefix caching: Enabled (`--enable-prefix-caching`)
- Max sequences: 128 (`--max-num-seqs=128`)

### KServe Integration

- **Declarative management** via `LLMInferenceService` CRD
- **Auto-created resources**: InferencePool, HTTPRoute, Service
- **TLS certificates**: KServe-issued, auto-mounted at `/var/run/kserve/tls/`
- **Health probes**: HTTPS-based liveness/readiness checks

### Istio Service Mesh

- **mTLS**: Automatic sidecar-to-sidecar encryption
- **Sidecar injection**: Enabled via namespace label `istio-injection: enabled`
- **Gateway**: Centralized ingress at `opendatahub` namespace
- **HTTPRoute**: PathPrefix routing with URL rewriting

## References

- **Repository Documentation**: `docs/customer-guides/` for comprehensive deployment guides
- **EPP Scheduler Bug**: `docs/BUG-EPP-Scheduler-ALPN.md` for multi-replica limitations
- **vLLM Documentation**: https://docs.vllm.ai/en/latest/features/prefix_caching.html
- **KServe Documentation**: https://kserve.github.io/website/
- **Istio Documentation**: https://istio.io/latest/docs/

## Support

For issues or questions:

1. Check `docs/customer-guides/troubleshooting.md`
2. Review `docs/customer-guides/faq.md`
3. Open an issue in this repository

## License

See repository root for license information.
