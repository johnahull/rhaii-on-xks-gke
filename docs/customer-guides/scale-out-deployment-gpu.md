# High-Throughput Scale-Out Deployment (GPU)

Deploy 3-replica vLLM service with prefix caching for high throughput on GPU T4.

## Overview

Similar to [Scale-Out Deployment (TPU)](scale-out-deployment-tpu.md) but adapted for GPU T4.

**Performance:**
- ~18 req/s parallel (vs 5-6 req/s single-model)
- ~4.8 req/s serial (vs 1.5 req/s single-model)
- 3.2× throughput improvement

**Cost:**
- Running: ~$228/day ($6,840/month)
- vs Single-model: 2.85× cost for 3.2× throughput
- Lower than TPU scale-out ($377/day)

## Prerequisites

- ✅ Single-model GPU deployment tested
- ✅ GPU quota: 3 GPUs minimum
- ✅ Budget approved (~$228/day)

## Key Differences from TPU

- Machine type: `n1-standard-4` (vs `ct6e-standard-4t`)
- Accelerator: `nvidia-tesla-t4` (vs TPU topology)
- Image: `vllm-cuda-rhel9` (vs `vllm-tpu-rhel9`)
- Lower cost, lower performance than TPU

## Deployment Steps

Same as TPU scale-out:

1. Delete single-model deployment
2. Scale GPU node pool to 3 nodes
3. Deploy scale-out configuration
4. Apply NetworkPolicies
5. Verify cache-aware routing

```bash
# Scale GPU node pool
gcloud container clusters resize rhaii-cluster \
  --node-pool gpu-pool \
  --num-nodes 3 \
  --zone us-central1-a

# Deploy
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml
```

## Performance

**Expected:**
- Throughput: ~18 req/s (parallel)
- Latency: <300ms P50
- Cost-per-request: Better than single-model

## Reference

**Manifest:** `deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml`

**Cost:** ~$228/day ($6,840/month)

**Performance:** ~18 req/s parallel, ~4.8 req/s serial

See [Scale-Out Deployment (TPU)](scale-out-deployment-tpu.md) for detailed procedures.
