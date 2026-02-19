# Simple vLLM Prefix Caching Demo

Single-replica deployment demonstrating vLLM prefix caching on GKE with KServe and Istio.

## Overview

This pattern demonstrates vLLM prefix caching achieving 60-75% latency reduction on repeated prompt prefixes. Single-replica deployment sidesteps the EPP scheduler ALPN bug while proving cache effectiveness.

**What this includes:**
- vLLM prefix caching (60-75% latency speedup on repeated prefixes)
- KServe LLMInferenceService for declarative vLLM management
- Istio service mesh integration with mTLS
- OpenAI-compatible API endpoints
- Single replica (1 node) deployment

**What this doesn't include:**
- Cache-aware routing across replicas (requires EPP scheduler - blocked by ALPN bug)
- Multi-replica scale-out
- EnvoyFilters or NetworkPolicies

## Why Single Replica

The EPP scheduler has a critical ALPN bug that prevents cache-aware routing across multiple replicas. See `docs/BUG-EPP-Scheduler-ALPN.md` for details.

Single-replica deployment characteristics:
- Simpler configuration (no EnvoyFilters needed)
- Lower cost (1 node vs 3 nodes)
- All requests naturally hit same cache (guaranteed cache hits)
- Proves caching works while avoiding EPP scheduler bug

To scale to multi-replica, see production deployment guides when EPP scheduler is fixed.

## Deployment Guides

### TPU v6e Deployment

[deployment-tpu.md](deployment-tpu.md) - Complete deployment guide for TPU

- Performance: ~8.3 req/s parallel, ~2.1 req/s serial
- Cache speedup: 62% (215ms → 82ms)
- Cost: ~$15/day (1 TPU node with 4 chips)
- Deployment time: ~45 minutes

Includes: cluster creation, operator installation, deployment steps, verification, troubleshooting

### GPU T4 Deployment

[deployment-gpu.md](deployment-gpu.md) - Complete deployment guide for GPU

- Performance: ~6 req/s parallel, ~1.6 req/s serial
- Cache speedup: 61% (280ms → 110ms)
- Cost: ~$12/day (1 GPU node)
- Deployment time: ~45 minutes

Includes: cluster creation, GPU Operator installation, RHAII operators, deployment steps, verification, troubleshooting

## Performance Comparison

**Single-replica performance:**

| Metric | TPU v6e | GPU T4 |
|--------|---------|---------|
| Parallel throughput | ~8.3 req/s | ~6 req/s |
| Serial throughput | ~2.1 req/s | ~1.6 req/s |
| Cache speedup | 62% | 61% |
| First request (cache miss) | 215ms | 280ms |
| Cached request (cache hit) | 82ms | 110ms |
| Cost per day | ~$15 | ~$12 |
| Accelerator | 4 TPU chips | 1 T4 GPU |

Cache effectiveness is identical across accelerators - the 60-75% speedup demonstrates vLLM prefix caching works regardless of hardware.

**vs. 3-replica production deployment:**

| Aspect | Single-replica | 3-replica |
|--------|----------------|-----------|
| Replicas | 1 | 3 |
| Throughput (TPU) | ~8.3 req/s | ~25 req/s |
| Throughput (GPU) | ~6 req/s | ~18 req/s |
| Cache speedup | 60-75% | 60-75% |
| Latency (cached) | 82-110ms | 82-110ms |
| Cost (TPU) | ~$15/day | ~$46/day |
| Cost (GPU) | ~$12/day | ~$36/day |
| Nodes | 1 | 3 |
| EPP scheduler | Not needed | Required (blocked) |
| EnvoyFilters | Not deployed | Required |
| Deployment time | ~45 min | ~50 min |

## Quick Start

Prerequisites:
- GKE cluster with TPU v6e or GPU T4 node pool
- RHAII operators installed (cert-manager, Istio, KServe, LWS)
- GPU Operator installed (GPU deployments only)
- Secrets configured (Red Hat pull secret, HuggingFace token)

Deploy:

```bash
# Create namespace
kubectl apply -f namespace-rhaii-inference.yaml

# Deploy LLMInferenceService (choose TPU or GPU)
kubectl apply -f llmisvc-tpu-single-replica.yaml  # TPU
# OR
kubectl apply -f llmisvc-gpu-single-replica.yaml  # GPU

# Deploy HTTPRoute
kubectl apply -f httproute-health-models.yaml

# Verify deployment
./scripts/verify-deployment.sh
./scripts/test-cache-routing.sh
```

See deployment guides above for complete step-by-step instructions.

## Manifests

| File | Purpose | Required |
|------|---------|----------|
| `namespace-rhaii-inference.yaml` | Namespace with Istio injection | Yes |
| `llmisvc-tpu-single-replica.yaml` | TPU single-replica deployment | TPU deployments |
| `llmisvc-gpu-single-replica.yaml` | GPU single-replica deployment | GPU deployments |
| `httproute-health-models.yaml` | HTTPRoute for health/models endpoints | Yes |

Not included (vs production):
- EnvoyFilters (no EPP scheduler for single replica)
- NetworkPolicies (simplified demo)

## Testing

### Automated Cache Test

```bash
./scripts/test-cache-routing.sh
```

Expected results:
- First request: ~215ms (TPU) or ~280ms (GPU) - cache miss
- Subsequent requests: ~82ms (TPU) or ~110ms (GPU) - cache hits
- Average speedup: 60-75%

### Manual Testing

```bash
# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')

# Health check
curl -k https://$GATEWAY_IP/rhaii-inference/qwen-3b-{tpu|gpu}-svc/health

# List models
curl -k https://$GATEWAY_IP/rhaii-inference/qwen-3b-{tpu|gpu}-svc/v1/models

# Inference request
curl -k -X POST https://$GATEWAY_IP/rhaii-inference/qwen-3b-{tpu|gpu}-svc/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/mnt/models",
    "prompt": "You are a helpful AI assistant. What is 2+2?",
    "max_tokens": 50
  }'
```

## Understanding Prefix Caching

vLLM prefix caching stores the computed KV cache for common prompt prefixes. When a new request shares the same prefix, vLLM reuses the cached computation instead of recalculating from scratch.

Example:

```
Request 1: "You are a helpful AI assistant. Please analyze X..."
           └─ Compute full prompt (slow)

Request 2: "You are a helpful AI assistant. Please analyze Y..."
           └─ Reuse cached prefix "You are a helpful AI..." (fast)
              └─ Only compute new tokens "analyze Y..."
```

Impact:
- 60-75% latency reduction on repeated prompts
- Higher throughput (more requests/second with same hardware)
- Lower cost per request

Best practices:
1. Use consistent system prompts across requests
2. Design prompts with reusable prefixes
3. Enable cache-aware routing for multi-replica (requires EPP scheduler fix)
4. Monitor cache hit rates via vLLM metrics

Cache metrics:
```bash
POD_NAME=$(kubectl get pods -n rhaii-inference -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -n rhaii-inference -c main -- \
  curl -sk https://localhost:8000/metrics | grep prefix_cache
```

Expected after testing:
```
vllm:prefix_cache_queries_total 10.0
vllm:prefix_cache_hits_total 9.0     # 90% hit rate
vllm:prefix_cache_misses_total 1.0
```

## Next Steps

### Explore OpenAI-Compatible API

```bash
# Chat completions
curl -k -X POST https://$GATEWAY_IP/rhaii-inference/qwen-3b-{tpu|gpu}-svc/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/mnt/models",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is machine learning?"}
    ]
  }'

# Embeddings (if model supports)
curl -k -X POST https://$GATEWAY_IP/rhaii-inference/qwen-3b-{tpu|gpu}-svc/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/mnt/models",
    "input": "The quick brown fox"
  }'
```

### Test Different Models

Edit the manifest to use different models:
```yaml
# In llmisvc-{tpu|gpu}-single-replica.yaml
spec:
  model:
    uri: hf://meta-llama/Llama-3.1-8B-Instruct
    name: meta-llama/Llama-3.1-8B-Instruct
```

Recommended models:
- Small (2-3B): `google/gemma-2b-it`, `microsoft/Phi-3-mini-4k-instruct`
- Medium (7-8B): `mistralai/Mistral-7B-Instruct-v0.3`, `meta-llama/Llama-3.1-8B-Instruct`
- Code: `codellama/CodeLlama-7b-Instruct-hf`

### Monitor with Prometheus

```bash
# Port-forward to vLLM pod
kubectl port-forward $POD_NAME -n rhaii-inference 8000:8000

# Access metrics
curl -k https://localhost:8000/metrics
```

Key metrics:
- `vllm:prefix_cache_hits_total` - Cache hit count
- `vllm:prefix_cache_misses_total` - Cache miss count
- `vllm:num_requests_running` - Active requests
- `vllm:gpu_cache_usage_perc` - GPU KV cache utilization

### Scale to Multi-Replica

When the EPP scheduler ALPN bug is resolved:

1. Follow production deployment guides:
   - [TPU Production Deployment](../../../docs/deployment-tpu.md)
   - [GPU Production Deployment](../../../docs/deployment-gpu.md)

2. Deploy EnvoyFilters for cache-aware routing
3. Scale to 3 replicas for higher throughput
4. Achieve 3x throughput with same cache speedup

## Architecture

```
External Request
    ↓
GCP Load Balancer
    ↓
Istio Gateway (opendatahub namespace)
    ↓ mTLS
HTTPRoute (rhaii-inference namespace)
    ↓
InferencePool (single backend)
    ↓
vLLM Pod (qwen-3b-{tpu|gpu}-svc-0-0)
    ├─ Istio sidecar (mTLS termination)
    ├─ vLLM main container (HTTPS with KServe certs)
    └─ Prefix cache (in-memory KV cache)
    ↓
First request: Cache MISS (~215-280ms)
Subsequent requests: Cache HIT (~82-110ms)
```

## Technical Details

### vLLM Configuration

TPU deployment:
- Model: `Qwen/Qwen2.5-3B-Instruct`
- Precision: FP16 (`--dtype=half`)
- Max context: 2048 tokens (`--max-model-len=2048`)
- Tensor parallelism: 4 chips (`--tensor-parallel-size=4`)
- Prefix caching: Enabled (`--enable-prefix-caching`)
- Max sequences: 128 (`--max-num-seqs=128`)

GPU deployment:
- Model: `Qwen/Qwen2.5-3B-Instruct`
- Precision: FP16 (`--dtype=half`)
- Max context: 4096 tokens (`--max-model-len=4096`)
- GPU memory: 85% (`--gpu-memory-utilization=0.85`)
- Prefix caching: Enabled (`--enable-prefix-caching`)
- Max sequences: 128 (`--max-num-seqs=128`)

### KServe Integration

- Declarative management via `LLMInferenceService` CRD
- Auto-created resources: InferencePool, HTTPRoute, Service
- TLS certificates: KServe-issued, auto-mounted at `/var/run/kserve/tls/`
- Health probes: HTTPS-based liveness/readiness checks

### Istio Service Mesh

- mTLS: Automatic sidecar-to-sidecar encryption
- Sidecar injection: Enabled via namespace label `istio-injection: enabled`
- Gateway: Centralized ingress at `opendatahub` namespace
- HTTPRoute: PathPrefix routing with URL rewriting

## Troubleshooting

See comprehensive troubleshooting in deployment guides:
- [TPU Troubleshooting](deployment-tpu.md#troubleshooting)
- [GPU Troubleshooting](deployment-gpu.md#troubleshooting)

Common issues:
1. Pod not starting: Check pull secret, HuggingFace token, TPU/GPU availability
2. No external IP on Gateway: Wait 2-3 minutes for load balancer provisioning
3. Inference requests failing: Verify Gateway IP, HTTPRoute, pod readiness
4. Low cache speedup: Check prefix caching enabled, use longer test prompts

Quick diagnostics:
```bash
# Check deployment health
./scripts/verify-deployment.sh

# Check pod status
kubectl get pods -n rhaii-inference

# View logs
POD_NAME=$(kubectl get pods -n rhaii-inference -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD_NAME -c main -n rhaii-inference
```

## References

Repository documentation:
- [Prerequisites Guide](../../../docs/prerequisites.md)
- [Operator Installation](../../../docs/operator-installation.md)
- [Verification and Testing](../../../docs/verification-testing.md)
- [Troubleshooting Guide](../../../docs/troubleshooting.md)
- [FAQ](../../../docs/faq.md)

Production deployment guides:
- [TPU Production Deployment](../../../docs/deployment-tpu.md) - 3-replica with cache-aware routing
- [GPU Production Deployment](../../../docs/deployment-gpu.md) - 3-replica with cache-aware routing

External resources:
- [EPP Scheduler ALPN Bug](../../../docs/BUG-EPP-Scheduler-ALPN.md) - Why multi-replica is blocked
- [vLLM Prefix Caching Documentation](https://docs.vllm.ai/en/latest/features/prefix_caching.html)
- [KServe Documentation](https://kserve.github.io/website/)
- [Istio Documentation](https://istio.io/latest/docs/)

## Support

For issues or questions:

1. Check deployment guides (deployment-tpu.md or deployment-gpu.md)
2. Review troubleshooting sections
3. Check [FAQ](../../../docs/faq.md)
4. Open an issue in this repository
