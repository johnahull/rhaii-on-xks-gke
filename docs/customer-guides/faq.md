# Frequently Asked Questions (FAQ)

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

**Recommendation:** Scale in increments of 1-2 replicas, test performance at each level.

---

### What's the minimum GCP quota needed?

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

**Recommendation:** See Pattern 2 (multi-model) documentation for advanced multi-model serving.

---

## Operations

### How do I scale to zero?

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

**Scale back up:**
```bash
gcloud container clusters resize CLUSTER_NAME \
  --node-pool tpu-pool \
  --num-nodes 1 \
  --zone ZONE
```

**Startup time:** ~5-10 minutes for nodes + pod scheduling

---

### How long does it take to deploy from scratch?

**Total time: ~50 minutes**

Breakdown:
1. Prerequisites (one-time): Variable (tools + quotas)
2. Validation checks: ~3 minutes
3. Cluster creation: ~20 minutes
4. Operator installation: ~10 minutes
5. Workload deployment (3 replicas): ~12 minutes
6. EnvoyFilter + NetworkPolicies: ~2 minutes
7. Verification: ~5 minutes

**Subsequent deployments:** ~35 minutes (skip prerequisites)

---

### Can I use this in production?

**Yes.** The deployment guides include NetworkPolicies for traffic isolation, and the Istio service mesh provides mTLS for pod-to-pod communication. Additional hardening (resource limits, HPA, monitoring) should be configured based on your organization's requirements.

---

### How do I avoid repeating --project and --zone in every command?

**Use environment variables** to set common configuration values once:

**Option 1: direnv (automatic):**
```bash
cp .envrc.example .envrc
# Edit .envrc with your values
direnv allow .
```

**Option 2: Manual sourcing:**
```bash
cp env.sh.example env.sh
# Edit env.sh with your values
source env.sh
```

**Supported variables:**
- `PROJECT_ID` - GCP project ID
- `ZONE` - GCP zone
- `CLUSTER_NAME` - Default cluster name
- `ACCELERATOR_TYPE` - Default accelerator (tpu/gpu)

**Example:**
```bash
export PROJECT_ID="ecoeng-llmd"
export ZONE="europe-west4-a"

# Simplified commands
./scripts/create-gke-cluster.sh --tpu
./scripts/verify-deployment.sh --deployment scale-out
```

**CLI flags always override environment variables**, so you can still customize:
```bash
./scripts/create-gke-cluster.sh --tpu --zone us-east5-a
```

See [Environment Setup Guide](environment-setup.md) for complete instructions.

---

## Migration and Upgrades

### How do I upgrade to a newer vLLM version?

Update the image in the LLMInferenceService manifest:

```yaml
spec:
  image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:NEW_VERSION
```

Reapply:
```bash
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml
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
   ./scripts/verify-deployment.sh --deployment scale-out
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
