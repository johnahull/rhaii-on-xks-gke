# High-Throughput Scale-Out Deployment (TPU)

Deploy 3-replica vLLM service with prefix caching for high throughput on TPU v6e.

## Overview

**Performance:**
- ~25 req/s parallel (vs 7-8 req/s single-model)
- ~6.3 req/s serial (vs 1.9 req/s single-model)
- 3.3× throughput improvement

**Cost:**
- Running: ~$377/day ($11,310/month)
- vs Single-model: 2.9× cost for 3.3× throughput
- **Cost efficiency: 1.14× better cost-per-request**

**Use case:** Production workloads >10 req/s with shared prompts

---

## Prerequisites

- ✅ Single-model deployment successfully deployed and tested
- ✅ TPU quota: 12 chips minimum (3 nodes × 4 chips)
- ✅ Budget approved (~$377/day)
- ✅ Workload analysis confirms shared prompts benefit from caching

**Optional:** Configure [Environment Setup](environment-setup.md) to streamline deployment commands.

---

## Architecture

**Scale-out additions:**
- 3 replicas instead of 1
- Prefix caching enabled (--enable-prefix-caching)
- Cache-aware routing via EnvoyFilter
- NetworkPolicies for security

**Request flow with caching:**
```
Request with prefix "Translate to French:"
    ↓
Istio Gateway
    ↓
EnvoyFilter (hash prefix, route to same replica)
    ↓
Replica 2 (has cached prefix)
    ↓
Fast response (~50ms vs ~200ms)
```

---

## Deployment Steps

### Step 1: Delete Single-Model Deployment

```bash
# Delete existing deployment
kubectl delete llminferenceservice gemma-2b-tpu-svc

# Wait for resources to be released
kubectl get pods -w
```

### Step 2: Scale Node Pool to 3 Nodes

```bash
gcloud container clusters resize rhaii-cluster \
  --node-pool tpu-pool \
  --num-nodes 3 \
  --zone europe-west4-a

# Wait for nodes to be ready (~10 minutes)
kubectl get nodes -w
```

### Step 3: Deploy Scale-Out Configuration

```bash
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml

# Monitor deployment
kubectl get llminferenceservice -w
```

**Key differences in manifest:**
```yaml
spec:
  replicas: 3  # vs 1 in single-model
  extraArgs:
    - "--enable-prefix-caching"  # Enable caching
```

### Step 4: Apply NetworkPolicies

```bash
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/networkpolicies/
```

### Step 5: Verify Cache-Aware Routing

```bash
# Test that requests with same prefix go to same replica
for i in {1..10}; do
  curl -s -X POST http://$GATEWAY_IP/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "google/gemma-2b-it", "prompt": "Translate to French: Hello", "max_tokens": 10}' | \
  jq -r '.headers."x-envoy-upstream-service-time"'
done

# All requests should show similar low latency (cache hit)
```

---

## Performance Validation

### Load Testing

```bash
# Run benchmark
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

---

## Operational Procedures

### Scale Up/Down

**Add more replicas:**
```yaml
spec:
  replicas: 5  # Scale to 5
```

Requires 20 TPU chips (5 nodes × 4 chips)

**Scale down:**
```yaml
spec:
  replicas: 2  # Scale to 2
```

### Rolling Updates

**Update vLLM version:**
```yaml
spec:
  image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.3.0  # New version
```

KServe performs rolling update automatically, maintaining availability.

---

## Cost Management

**Scale to zero when not in use:**
```bash
# Scale node pool to zero
gcloud container clusters resize rhaii-cluster \
  --node-pool tpu-pool \
  --num-nodes 0 \
  --zone europe-west4-a

# Savings: $371/day (from $377 to $6 cluster overhead)
```

**Scheduled scaling:**
See [Cost Management Guide](cost-management.md) for automation.

---

## Migration from Single-Model

**Checklist:**
1. Validate single-model deployment working
2. Request additional TPU quota (12 chips total)
3. Budget approval for increased cost
4. Delete single-model deployment
5. Scale node pool to 3
6. Deploy scale-out configuration
7. Verify cache routing
8. Performance benchmark
9. Monitor for 24-48 hours

**Rollback procedure:**
1. Delete scale-out deployment
2. Scale node pool to 1
3. Redeploy single-model configuration

---

## Monitoring

```bash
# Check all replicas running
kubectl get pods -l serving.kserve.io/inferenceservice

# Resource usage across nodes
kubectl top nodes

# Per-pod metrics
kubectl top pods -l serving.kserve.io/inferenceservice
```

---

## Troubleshooting

**Only 1/3 replicas starting:**
- Check TPU quota: Need 12 chips
- Check node pool size: Should have 3 nodes
- View events: `kubectl get events --sort-by='.lastTimestamp'`

**Cache routing not working:**
- Verify EnvoyFilter applied
- Check request headers include consistent prefixes
- Test with identical prompts

See [Troubleshooting Guide](troubleshooting.md).

---

## Next Steps

- [Production Hardening](production-hardening.md) - Security and reliability
- [Cost Management](cost-management.md) - Optimize costs
- [Verification Testing](verification-testing.md) - Comprehensive validation

---

## Reference

**Manifest:** `deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml`

**Cost:** ~$377/day ($11,310/month)

**Performance:** ~25 req/s parallel, ~6.3 req/s serial
