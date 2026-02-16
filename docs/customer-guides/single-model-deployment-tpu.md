# Single-Model Deployment (TPU)

Detailed guide for deploying a single-model baseline vLLM inference service on TPU v6e.

## Overview

For a quick 30-minute deployment, see **[TPU Quickstart](quickstart-tpu.md)**.

This guide provides additional details, customization options, and production considerations.

---

## Prerequisites

- ✅ GKE cluster with TPU v6e node pool created
- ✅ RHAII operators installed (cert-manager, Istio, KServe, LWS)
- ✅ kubectl configured for cluster access
- ✅ Secrets applied (pull-secret, huggingface-token)

**Verify:**
```bash
./scripts/verify-deployment.sh --operators-only
```

---

## Deployment Architecture

```
User Request
    ↓
Istio Gateway (LoadBalancer)
    ↓
HTTPRoute (routing rules)
    ↓
InferencePool (KServe managed)
    ↓
vLLM Pod (TPU v6e, 4 chips)
```

**Components:**
- **Gateway:** External entry point with LoadBalancer IP
- **HTTPRoute:** Routes `/v1/*` to inference service
- **LLMInferenceService:** KServe CRD that creates InferencePool
- **InferencePool:** Manages vLLM pod lifecycle
- **vLLM Pod:** Runs vLLM with TPU backend (JAX/XLA)

---

## Manifest Explanation

**File:** `deployments/istio-kserve/baseline-pattern/manifests/llmisvc-tpu.yaml`

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: gemma-2b-tpu-svc
spec:
  # Model configuration
  model: "google/gemma-2b-it"
  dtype: "half"            # FP16 precision
  maxModelLen: 2048        # Max context length

  # TPU configuration
  image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.2.5
  tpuTopology: "2x2x1"     # 4 chips

  # Resources
  machineType: "ct6e-standard-4t"
  replicas: 1

  # Secrets
  imagePullSecrets:
    - name: rhaiis-pull-secret
  envFrom:
    - secretRef:
        name: huggingface-token
```

---

## Customization Options

### Change Model

**Supported models:**
```yaml
spec:
  model: "mistralai/Mistral-7B-Instruct-v0.3"  # 7B model
  maxModelLen: 4096  # Increase context length
```

**Larger models:**
- 7B models: Work well on TPU v6e
- 13B models: May require larger topology (2x2x2 = 8 chips)

### Adjust Context Length

```yaml
spec:
  maxModelLen: 4096  # Default: 2048
```

**Trade-off:** Longer context uses more memory, may reduce throughput

### Change Precision

```yaml
spec:
  dtype: "bfloat16"  # Alternative to half (FP16)
```

**Options:**
- `half` (FP16): Default, good balance
- `bfloat16`: Better numerical stability for some models
- `float32`: Highest precision, uses more memory

### Resource Limits

```yaml
spec:
  resources:
    limits:
      cpu: "16"
      memory: "64Gi"
    requests:
      cpu: "8"
      memory: "32Gi"
```

---

## Deployment Procedure

### Step 1: Apply Secrets

```bash
# Apply pull secret
kubectl apply -f redhat-pull-secret.yaml

# Apply HuggingFace token
kubectl apply -f huggingface-token-secret.yaml

# Verify
kubectl get secrets
```

### Step 2: Deploy LLMInferenceService

```bash
kubectl apply -f deployments/istio-kserve/baseline-pattern/manifests/llmisvc-tpu.yaml
```

### Step 3: Monitor Deployment

```bash
# Watch LLMInferenceService status
kubectl get llminferenceservice -w

# Check pods
kubectl get pods -l serving.kserve.io/inferenceservice

# View logs
kubectl logs -l serving.kserve.io/inferenceservice -f
```

**Expected timeline:**
- 0-2 min: Pod scheduling
- 2-5 min: Image pull
- 5-10 min: Model download
- 10+ min: READY=True

### Step 4: Get Gateway IP

```bash
export GATEWAY_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Gateway IP: $GATEWAY_IP"
```

### Step 5: Test Deployment

```bash
# Health check
curl http://$GATEWAY_IP/v1/health

# List models
curl http://$GATEWAY_IP/v1/models

# Test inference
curl -X POST http://$GATEWAY_IP/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-2b-it",
    "prompt": "Explain quantum computing:",
    "max_tokens": 100
  }'
```

---

## Production Considerations

### Enable mTLS

See [Production Hardening Guide](production-hardening.md) for:
- mTLS STRICT mode configuration
- Certificate management
- NetworkPolicy enforcement

### Resource Limits

Set appropriate limits to prevent resource exhaustion:
```yaml
spec:
  resources:
    limits:
      cpu: "16"
      memory: "64Gi"
```

### Monitoring

Set up monitoring:
```bash
kubectl top nodes
kubectl top pods -l serving.kserve.io/inferenceservice
```

### High Availability

For production, consider:
- [Scale-Out Deployment (TPU)](scale-out-deployment-tpu.md) for 3 replicas
- PodDisruptionBudget for maintenance windows
- Liveness and readiness probes

---

## Performance Tuning

### Batch Size

```yaml
spec:
  maxBatchSize: 256  # Default, adjust based on traffic
```

### Tensor Parallelism

For larger models:
```yaml
spec:
  tensorParallelSize: 2  # Split across 2 chips
```

### Quantization

For memory-constrained scenarios:
```yaml
spec:
  quantization: "awq"  # or "gptq"
```

---

## Troubleshooting

See [Troubleshooting Guide](troubleshooting.md) for common issues:

- LLMInferenceService not READY
- Model download failures
- TPU not detected
- Performance issues

---

## Next Steps

- **Scale out:** [High-Throughput Scale-Out (TPU)](scale-out-deployment-tpu.md)
- **Harden for production:** [Production Hardening](production-hardening.md)
- **Optimize costs:** [Cost Management](cost-management.md)

---

## Reference

**Manifest:** `deployments/istio-kserve/baseline-pattern/manifests/llmisvc-tpu.yaml`

**Performance:**
- Parallel requests: ~7-8 req/s
- Serial requests: ~1.9 req/s

**Cost:** ~$132/day ($3,960/month)
