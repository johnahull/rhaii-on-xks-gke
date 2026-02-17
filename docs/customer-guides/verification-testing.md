# Verification and Testing

Comprehensive post-deployment validation procedures.

## Automated Verification

Use the verification script for quick checks:

```bash
# Verify operators only
./scripts/verify-deployment.sh --operators-only

# Verify deployment
./scripts/verify-deployment.sh
```

## Manual Verification Checklist

### Operator Verification

```bash
# cert-manager
kubectl get pods -n cert-manager
# Expected: 3 pods Running

# Istio
kubectl get pods -n istio-system
# Expected: istiod and istio-ingressgateway Running

# KServe
kubectl get pods -n kserve
# Expected: kserve-controller-manager Running

# LWS
kubectl get pods -n lws-system
# Expected: lws-controller-manager Running
```

### Deployment Verification

```bash
# LLMInferenceService status
kubectl get llminferenceservice
# Expected: READY=True

# Inference pods
kubectl get pods -l serving.kserve.io/inferenceservice
# Expected: All Running

# Gateway IP assigned
kubectl get svc istio-ingressgateway -n istio-system
# Expected: EXTERNAL-IP present
```

### Endpoint Testing

```bash
export GATEWAY_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Health endpoint
curl http://$GATEWAY_IP/v1/health

# Models endpoint
curl http://$GATEWAY_IP/v1/models

# Completion endpoint
curl -X POST http://$GATEWAY_IP/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "google/gemma-2b-it", "prompt": "Test", "max_tokens": 10}'
```

## Performance Baseline

### Latency Test

```bash
time curl -X POST http://$GATEWAY_IP/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "google/gemma-2b-it", "prompt": "Hello", "max_tokens": 50}'

# Expected: <500ms after warmup
```

### Throughput Test

```bash
# Run benchmark
python3 benchmarks/python/benchmark_vllm.py \
  --endpoint http://$GATEWAY_IP/v1/completions \
  --model google/gemma-2b-it \
  --concurrent 5 \
  --duration 30
```

**Expected results:**

**TPU (3 replicas):**
- Parallel: ~25 req/s
- Latency: <200ms P50

**GPU (3 replicas):**
- Parallel: ~18 req/s
- Latency: <300ms P50

## Security Validation

### NetworkPolicy Testing

```bash
# List NetworkPolicies
kubectl get networkpolicy

# Test pod-to-pod communication
kubectl run test --image=curlimages/curl --rm -it -- \
  curl http://POD_IP:8000/v1/health
```

### mTLS Verification

```bash
# Check mTLS mode
kubectl get peerauthentication -n istio-system

# Verify certificates
kubectl get certificates --all-namespaces
```

## Resource Validation

```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -l serving.kserve.io/inferenceservice

# Accelerator allocation
kubectl describe nodes | grep -E "nvidia.com/gpu|cloud-tpus.google.com/chip"
```

## Success Criteria

✅ All operator pods Running
✅ LLMInferenceService READY=True
✅ Gateway external IP assigned
✅ Health endpoint returns 200
✅ Inference requests succeed
✅ Performance meets baseline
✅ Resource usage within limits

## Troubleshooting

If any checks fail, see [Troubleshooting Guide](troubleshooting.md).
