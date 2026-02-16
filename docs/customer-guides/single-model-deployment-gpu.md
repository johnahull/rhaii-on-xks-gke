# Single-Model Deployment (GPU)

Detailed guide for deploying a single-model baseline vLLM inference service on GPU T4.

## Quick Start

For a quick 30-minute deployment, see **[GPU Quickstart](quickstart-gpu.md)**.

## Overview

This guide is similar to [Single-Model Deployment (TPU)](single-model-deployment-tpu.md) but adapted for GPU T4.

**Key differences:**
- Image: `registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.0.0` (CUDA instead of TPU)
- Machine type: `n1-standard-4` (CPU + 1× T4 GPU)
- Backend: XFormers (T4 doesn't support FlashAttention-2)
- Performance: ~5-6 req/s parallel, ~1.5 req/s serial
- Cost: ~$80/day

## Manifest

**File:** `deployments/istio-kserve/baseline-pattern/manifests/llmisvc-gpu.yaml`

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: gemma-2b-gpu-svc
spec:
  model: "google/gemma-2b-it"
  dtype: "half"
  maxModelLen: 4096  # GPU has more context support than TPU in pattern1
  
  # GPU configuration
  image: registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.0.0
  machineType: "n1-standard-4"
  accelerator:
    type: "nvidia-tesla-t4"
    count: 1
  
  replicas: 1
```

## GPU-Specific Considerations

**Memory constraints:**
- T4 has 13.12 GiB memory
- 7B models fit (tight)
- 9B+ models won't fit
- Use `dtype: "half"` to save memory

**Performance:**
- Lower than TPU (~5-6 vs ~7-8 req/s)
- Good for development and PoC
- Latency typically <300ms

## Deployment

Same procedure as TPU deployment - see [Quickstart GPU](quickstart-gpu.md) or [Single-Model Deployment TPU](single-model-deployment-tpu.md) for steps.

## GPU-Specific Troubleshooting

**GPU not detected:**
```bash
# Verify GPU node exists
kubectl get nodes -o wide

# Check GPU allocation
kubectl describe nodes | grep nvidia.com/gpu
```

**DO NOT install GPU Operator** - GKE provides native GPU support.

## Next Steps

- [Scale-Out Deployment (GPU)](scale-out-deployment-gpu.md)
- [Production Hardening](production-hardening.md)
- [Cost Management](cost-management.md)
