# Frequently Asked Questions (FAQ)

## Deployment Decisions

### When should I use TPU vs GPU?

**Use TPU v6e when:**
- You need maximum performance (~7-8 req/s single, ~25 req/s scale-out)
- You have production workloads with consistent traffic
- Budget allows ~$132/day for single-model deployment
- Your zone has TPU v6e availability

**Use GPU T4 when:**
- You're doing PoC or development work
- You need lower costs (~$80/day for single-model)
- You need wider zone availability (20+ zones vs 5 zones)
- You want faster quota approval (instant vs 24-48h)

**Performance comparison:**
| Metric | GPU T4 | TPU v6e | Winner |
|--------|--------|---------|--------|
| Single-model throughput | 5-6 req/s | 7-8 req/s | TPU |
| Scale-out throughput | 18 req/s | 25 req/s | TPU |
| Cost (single) | $80/day | $132/day | GPU |
| Cost (scale-out) | $228/day | $377/day | GPU |
| Zone availability | Wide | Limited | GPU |
| Memory | 13.12 GiB | 16 GiB | TPU |

**Recommendation:** Start with GPU for PoC, upgrade to TPU for production.

---

### When should I use single-model vs scale-out deployment?

**Single-model deployment when:**
- Traffic <10 req/s
- Development or testing workloads
- Cost-sensitive deployments
- Getting started with RHAII
- Simple use case, single model

**Scale-out deployment (3 replicas) when:**
- Traffic >10 req/s
- Production workloads needing high availability
- Workloads with shared prompts (benefits from prefix caching)
- You can afford 2.9× cost for 3.3× throughput

**Cost-benefit analysis:**
- Single-model TPU: $132/day, ~7-8 req/s
- Scale-out TPU: $377/day (~2.9× cost), ~25 req/s (~3.3× throughput)
- **Result:** 1.14× better cost-per-request with scale-out

**Recommendation:** Start with single-model, scale when traffic consistently exceeds 10 req/s.

---

## Technical Questions

### Can I use models other than google/gemma-2b-it?

**Yes!** You can use any model compatible with vLLM.

**Recommended models by size:**

**Small (2-3B):**
- `google/gemma-2b-it` (default)
- `microsoft/Phi-3-mini-4k-instruct` (3.8B)

**Medium (7-8B):**
- `mistralai/Mistral-7B-Instruct-v0.3`
- `google/gemma-2-9b-it`
- `meta-llama/Llama-3.1-8B-Instruct` (requires license acceptance)

**Specialized:**
- `codellama/CodeLlama-7b-Instruct-hf`

**To change the model:**
Edit the LLMInferenceService manifest:
```yaml
spec:
  model: "mistralai/Mistral-7B-Instruct-v0.3"  # Change this
  dtype: "half"
  maxModelLen: 4096
```

**Considerations:**
- Larger models require more memory (may not fit on T4)
- Gated models require HuggingFace license acceptance
- Performance varies by model architecture

---

### How do I add more replicas beyond 3?

Edit the LLMInferenceService manifest:

```yaml
spec:
  replicas: 5  # Change from 3 to 5
```

Reapply:
```bash
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml
```

**Requirements:**
- Sufficient quota (5 replicas × 4 chips = 20 TPU chips for TPU v6e)
- Sufficient node pool capacity
- Cost increases linearly: 5 replicas ≈ $628/day (TPU)

**Recommendation:** Scale in increments of 1-2 replicas, test performance at each level.

---

### What's the minimum GCP quota needed?

**Single-model deployment:**

**TPU:**
- TPU v6e chips: 4 (one node)
- CPUs: 20
- In-use IP addresses: 5
- Load balancers: 2

**GPU:**
- T4 GPUs: 1
- CPUs: 20
- In-use IP addresses: 5
- Load balancers: 2

**Scale-out deployment (3 replicas):**

**TPU:**
- TPU v6e chips: 12 (three nodes)
- CPUs: 30
- In-use IP addresses: 10
- Load balancers: 2

**GPU:**
- T4 GPUs: 3
- CPUs: 30
- In-use IP addresses: 10
- Load balancers: 2

---

### Can I run multiple models simultaneously?

**Yes**, but it requires additional configuration:

1. Deploy separate LLMInferenceService for each model
2. Configure HTTPRoutes to route by model name
3. Ensure sufficient accelerator resources

**Example:**
- Model A on node pool 1
- Model B on node pool 2

**Cost:** Proportional to number of models (each needs dedicated accelerator)

**Recommendation:** See Pattern 2 (multi-model) documentation for advanced multi-model serving.

---

## Operations

### How do I scale to zero to save costs?

**Scale accelerator node pool to zero:**

```bash
# TPU
gcloud container clusters resize CLUSTER_NAME \
  --node-pool tpu-pool \
  --num-nodes 0 \
  --zone ZONE

# GPU
gcloud container clusters resize CLUSTER_NAME \
  --node-pool gpu-pool \
  --num-nodes 0 \
  --zone ZONE
```

**Cost when scaled to zero:**
- ~$6/day (cluster control plane + standard nodes)
- **Savings:** $126/day (TPU) or $74/day (GPU)

**Scale back up:**
```bash
gcloud container clusters resize CLUSTER_NAME \
  --node-pool tpu-pool \
  --num-nodes 1 \
  --zone ZONE
```

**Startup time:** ~5-10 minutes for nodes + pod scheduling

See [Cost Management Guide](cost-management.md) for automation.

---

### How long does it take to deploy from scratch?

**Total time: ~30-40 minutes**

Breakdown:
1. Prerequisites (one-time): Variable (tools + quotas)
2. Validation checks: ~3 minutes
3. Cluster creation: ~15 minutes
4. Operator installation: ~10 minutes
5. Workload deployment: ~10 minutes
6. Verification: ~3 minutes

**Subsequent deployments:** ~25 minutes (skip prerequisites)

---

### Can I use this in production?

**Yes**, with production hardening:

**Required steps:**
1. Enable mTLS STRICT mode
2. Apply NetworkPolicies
3. Configure resource limits and HPA
4. Set up monitoring (Prometheus/Grafana)
5. Configure backup/restore procedures
6. Implement disaster recovery plan

See [Production Hardening Guide](production-hardening.md) for checklist.

**Security considerations:**
- mTLS for pod-to-pod communication
- NetworkPolicy for traffic isolation
- RBAC for access control
- Secret management for credentials

---

## Costs

### What's included in the cost estimates?

**Cost estimates include:**
- Accelerator costs (TPU/GPU per hour)
- Compute node costs (n1-standard-4 or ct6e-standard-4t)
- GKE cluster overhead (control plane + standard nodes)

**NOT included:**
- Egress network traffic
- Persistent storage (if used)
- Load balancer egress (typically minimal)
- GCP project overhead

**Estimate accuracy:** ±10% depending on actual usage patterns

---

### How can I reduce costs?

**Top cost-saving strategies:**

1. **Scale to zero when not in use** (saves ~$126/day TPU, ~$74/day GPU)
2. **Use GPU for dev/test, TPU for production**
3. **Right-size models** (don't use 70B model if 7B works)
4. **Schedule scaling** (scale down overnight/weekends)
5. **Use committed use discounts** (30-70% savings for long-term)
6. **Monitor and optimize** (kubectl top nodes)

See [Cost Management Guide](cost-management.md) for details.

---

## Migration and Upgrades

### How do I migrate between deployment patterns?

**Single-model → Scale-out:**

1. Delete single-model deployment:
   ```bash
   kubectl delete llminferenceservice <name>
   ```

2. Scale node pool to 3 nodes:
   ```bash
   gcloud container clusters resize CLUSTER \
     --node-pool tpu-pool \
     --num-nodes 3 \
     --zone ZONE
   ```

3. Deploy scale-out configuration:
   ```bash
   kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml
   ```

**Scale-out → Single-model:**
Reverse the above steps, scale node pool back to 1.

**Downtime:** ~5-10 minutes during transition

---

### How do I upgrade to a newer vLLM version?

Update the image in the LLMInferenceService manifest:

```yaml
spec:
  image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:NEW_VERSION
```

Reapply:
```bash
kubectl apply -f deployments/istio-kserve/baseline-pattern/manifests/llmisvc-tpu.yaml
```

**KServe will perform rolling update automatically.**

**Downtime:** Minimal (rolling update maintains availability)

---

## Troubleshooting

### Where do I find logs?

**Operator logs:**
```bash
kubectl logs -n kserve deployment/kserve-controller-manager
kubectl logs -n istio-system deployment/istiod
```

**Application logs:**
```bash
kubectl logs -l serving.kserve.io/inferenceservice -f
```

**Events:**
```bash
kubectl get events --sort-by='.lastTimestamp'
```

---

### What if verification fails?

1. Run detailed verification:
   ```bash
   ./scripts/verify-deployment.sh --deployment single-model
   ```

2. Check specific component:
   ```bash
   kubectl describe llminferenceservice <name>
   kubectl describe pod <pod-name>
   ```

3. Review [Troubleshooting Guide](troubleshooting.md)

4. Check operator logs for specific errors

---

## Support

### Where can I get help?

1. **This documentation:**
   - [Troubleshooting Guide](troubleshooting.md)
   - [Prerequisites](prerequisites.md)
   - [Operator Installation](operator-installation.md)

2. **Official repositories:**
   - RHAII on XKS: https://github.com/opendatahub-io/rhaii-on-xks
   - KServe: https://kserve.github.io/website/
   - Istio: https://istio.io/latest/docs/

3. **Verification scripts:**
   ```bash
   ./scripts/verify-deployment.sh --operators-only
   ./scripts/preflight-check.sh --customer
   ```

---

**Have a question not answered here?** Check [Troubleshooting](troubleshooting.md) or review the detailed deployment guides.
