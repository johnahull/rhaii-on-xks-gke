# 30-Minute TPU Quickstart

Deploy RHAII vLLM on Google Cloud TPU v6e (Trillium) in 30-40 minutes.

## Overview

**What you'll deploy:**
- GKE cluster with TPU v6e node pool
- RHAII operators (cert-manager, Istio, KServe, LWS)
- Single-model vLLM inference service (google/gemma-2b-it)

**Performance:**
- ~7-8 req/s parallel requests
- ~1.9 req/s serial requests

**Cost:**
- Running: ~$132/day ($3,960/month)
- Scaled to zero: ~$6/day (cluster overhead only)

**Time:** ~30-40 minutes total

---

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Google Cloud account with billing enabled
- [ ] Project: `ecoeng-llmd` (or your project) with Owner/Editor role
- [ ] `gcloud` CLI installed and authenticated
- [ ] `kubectl` CLI installed
- [ ] Red Hat registry credentials in `11009103-jhull-svc-pull-secret.yaml`
- [ ] HuggingFace token for model access
- [ ] TPU v6e quota: 4 chips minimum (12 chips for scale-out)

**Need help?** See [Prerequisites Guide](prerequisites.md) for detailed setup instructions.

---

## Step 1: Run Validation Checks (3 minutes)

Validate your environment before creating resources:

```bash
# Navigate to repository
cd /path/to/llm-d-xks-gke

# Run preflight check with customer-friendly output
./scripts/preflight-check.sh \
  --deployment istio-kserve/baseline-pattern \
  --accelerator tpu \
  --zone us-central1-b \
  --customer
```

**Success criteria:**
- ✅ All tools installed (gcloud, kubectl, jq)
- ✅ GCP authentication valid
- ✅ Required permissions granted
- ✅ Secrets exist (pull-secret, huggingface-token)

**If checks fail:** See troubleshooting output for specific fixes.

---

## Step 2: Create GKE Cluster with TPU (15 minutes)

Create a production-ready GKE cluster with TPU v6e node pool:

```bash
# Interactive cluster creation (recommended)
./scripts/create-gke-cluster.sh --tpu

# Or specify options explicitly
./scripts/create-gke-cluster.sh --tpu \
  --project ecoeng-llmd \
  --zone us-central1-b \
  --cluster-name rhaii-tpu-cluster
```

**What this does:**
1. Validates accelerator availability in zone
2. Checks node pool prerequisites and quota
3. Creates GKE cluster (control plane + standard nodes)
4. Creates TPU v6e node pool (ct6e-standard-4t, 4 chips)
5. Configures kubectl access

**Success criteria:**
- ✅ Cluster status: RUNNING
- ✅ TPU node pool created
- ✅ kubectl can list nodes

**Time:** ~15 minutes (5 min control plane + 10 min TPU node pool)

---

## Step 3: Install Operators via RHAII on XKS (10 minutes)

Install required operators using the official RHAII on XKS repository:

```bash
# Clone RHAII on XKS repository (if not already cloned)
cd ~/workspace  # or your preferred location
if [ ! -d "rhaii-on-xks" ]; then
  git clone https://github.com/opendatahub-io/rhaii-on-xks.git
fi

# Navigate to RHAII on XKS repository
cd rhaii-on-xks

# Deploy all operators
make deploy-all

# Verify operator status
make status
```

**What this installs:**
- cert-manager (certificate management)
- Red Hat OpenShift Service Mesh (Istio)
- KServe v0.15 (inference serving)
- LeaderWorkerSet (LWS) controller

**Success criteria:**
- ✅ All operator pods Running
- ✅ cert-manager webhook ready
- ✅ Istio control plane ready
- ✅ KServe controller ready

**Verify from llm-d-xks-gke repository:**
```bash
cd /path/to/llm-d-xks-gke
./scripts/verify-deployment.sh --operators-only
```

**Time:** ~10 minutes

**Troubleshooting:** See [Operator Installation Guide](operator-installation.md)

---

## Step 4: Deploy Single-Model Workload (10 minutes)

Deploy the baseline single-model vLLM inference service:

```bash
# Apply secrets (if not already applied)
kubectl apply -f 11009103-jhull-svc-pull-secret.yaml
kubectl apply -f huggingface-token-secret.yaml

# Deploy LLMInferenceService
kubectl apply -f deployments/istio-kserve/baseline-pattern/manifests/llmisvc-tpu.yaml

# Monitor deployment
kubectl get llminferenceservice -w
```

**Expected output:**
```
NAME                READY   URL
gemma-2b-tpu-svc    True    http://...
```

**Wait for READY=True** (may take 5-10 minutes for pod creation and model download)

**Success criteria:**
- ✅ LLMInferenceService READY=True
- ✅ Inference pods running
- ✅ Gateway has external IP

**Time:** ~10 minutes (pod scheduling + model download)

---

## Step 5: Test Deployment (3 minutes)

Verify the deployment is working:

```bash
# Automated verification
./scripts/verify-deployment.sh --deployment single-model

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

---

## 🎉 Success!

Your RHAII TPU deployment is ready!

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
# Check pod status
kubectl get pods -l serving.kserve.io/inferenceservice

# View logs
kubectl logs -l serving.kserve.io/inferenceservice -f

# Check resource usage
kubectl top nodes
kubectl top pods
```

---

## What's Next?

### Scale to High-Throughput (>10 req/s)

Ready for production traffic? Scale to 3 replicas with prefix caching:

**[Scale-Out Deployment Guide (TPU)](scale-out-deployment-tpu.md)**
- 3× capacity (~25 req/s parallel)
- Prefix caching for shared prompts
- High availability
- Cost: ~$377/day

### Production Hardening

Prepare for production:

**[Production Hardening Guide](production-hardening.md)**
- mTLS STRICT mode
- NetworkPolicy enforcement
- Resource limits and HPA
- Monitoring and alerting

### Cost Optimization

Reduce costs when not in use:

**[Cost Management Guide](cost-management.md)**
- Scale to zero procedures
- Scheduling strategies
- Budget alerts

---

## Cost Management

**Scale down when not in use:**

```bash
# Scale TPU node pool to zero
gcloud container clusters resize rhaii-tpu-cluster \
  --node-pool tpu-pool \
  --num-nodes 0 \
  --zone us-central1-b

# Scale back up
gcloud container clusters resize rhaii-tpu-cluster \
  --node-pool tpu-pool \
  --num-nodes 1 \
  --zone us-central1-b
```

**Cost savings:**
- Running: ~$132/day
- Scaled to zero: ~$6/day (cluster overhead)
- **Daily savings: ~$126**

---

## Troubleshooting

**LLMInferenceService not READY:**
- Check pod status: `kubectl get pods -l serving.kserve.io/inferenceservice`
- View logs: `kubectl logs <pod-name>`
- Common cause: Image pull errors (check pull secret)

**No external IP on Gateway:**
- Wait 2-3 minutes for load balancer provisioning
- Check: `kubectl get svc istio-ingressgateway -n istio-system`

**Inference requests failing:**
- Verify Gateway IP: `kubectl get svc -n istio-system`
- Check HTTPRoute: `kubectl get httproute`
- Test health endpoint first: `curl http://$GATEWAY_IP/v1/health`

**See [Troubleshooting Guide](troubleshooting.md) for more solutions.**

---

## Reference

**Repository Structure:**
```
llm-d-xks-gke/
├── scripts/
│   ├── create-gke-cluster.sh
│   ├── verify-deployment.sh
│   └── preflight-check.sh
├── deployments/istio-kserve/baseline-pattern/
│   ├── manifests/
│   │   └── llmisvc-tpu.yaml
│   └── docs/
└── docs/customer-guides/
```

**Estimated Costs (us-central1-b):**
- Single-model TPU: ~$132/day, $3,960/month
- Control plane: ~$6/day (when scaled to zero)

**Performance Benchmarks:**
- Parallel requests: ~7-8 req/s
- Serial requests: ~1.9 req/s
- First inference: ~2-3s (XLA compilation)
- Subsequent: <200ms

---

**Need help?** Check [FAQ](faq.md) or [Troubleshooting](troubleshooting.md)
