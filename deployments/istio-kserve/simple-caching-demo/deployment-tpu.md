# Simple vLLM Prefix Caching Demo (TPU)

Deploy a single-replica vLLM inference service on TPU v6e to demonstrate prefix caching effectiveness.

**Purpose:** Quick proof of concept to demonstrate vLLM prefix caching achieving 60-75% latency reduction without multi-replica complexity.

## Overview

**What you'll deploy:**
- GKE cluster with single-node TPU v6e pool (4 TPU chips)
- RHAII operators (cert-manager, Istio, KServe, LWS)
- Single-replica vLLM inference service with prefix caching enabled
- Basic HTTP routing (no EPP scheduler or EnvoyFilters)
- Lightweight demo for testing and evaluation

**Performance:**
- ~8.3 req/s parallel requests
- ~2.1 req/s serial requests
- **Cache speedup: 60-75%** (215ms → 82ms on repeated prefixes)

**Time:** ~45 minutes total (faster than 3-replica deployment)

**💰 Cost:** ~$15/day if left running (1 TPU node). Remember to scale down when not testing!

---

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Google Cloud account with billing enabled
- [ ] Project: `YOUR_PROJECT` (or your project) with Owner/Editor role
- [ ] `gcloud` CLI installed and authenticated
- [ ] `kubectl` CLI installed
- [ ] Red Hat registry credentials in `redhat-pull-secret.yaml` (create from `templates/redhat-pull.yaml.template`)
- [ ] HuggingFace token in `huggingface-token-secret.yaml` (create from `templates/huggingface-token.yaml.template`)
- [ ] **TPU v6e quota: 4 chips minimum** (1 node × 4 chips)

**Need help?** See [Prerequisites Guide](../../../docs/prerequisites.md) for detailed setup instructions.

---

## Architecture

This deployment demonstrates vLLM prefix caching with a simple single-replica architecture.

### Deployment Overview

```mermaid
graph TB
    subgraph cluster["GKE Cluster (rhaii-tpu-demo-cluster)"]
        subgraph nodes["Node Pools"]
            subgraph stdpool["Standard Pool (2 nodes)"]
                STD1[Standard Node]
                STD2[Standard Node]
            end
            subgraph tpupool["TPU Pool (1 node)"]
                TPU1["TPU Node 1<br/>ct6e-standard-4t<br/>4x TPU v6e chips"]
            end
        end

        subgraph operators["Operator Namespaces (Managed)"]
            CM["cert-manager<br/>TLS certificates"]
            ISTIO["istio-system<br/>Service mesh"]
            ODH["opendatahub<br/>KServe + Gateway"]
            LWS["openshift-lws-operator<br/>Workload controller"]
        end

        subgraph workload["rhaii-inference Namespace (Your Workload)"]
            VLLM1["vLLM Replica<br/>Qwen-2.5-3B<br/>Prefix caching<br/>Tensor parallel: 4"]
        end
    end

    TPU1 -.->|4 TPU chips| VLLM1

    style workload fill:#e1f5ff
    style operators fill:#fff4e1
```

### Request Flow with Prefix Caching

```mermaid
sequenceDiagram
    participant Client
    participant Gateway as Istio Gateway<br/>(LoadBalancer)
    participant HTTPRoute as HTTPRoute<br/>(Path routing)
    participant VLLM as vLLM Replica<br/>(TPU Node)

    Note over Client,VLLM: Request 1: "Translate to French: Hello"
    Client->>Gateway: POST /v1/completions
    Gateway->>HTTPRoute: Route by path
    HTTPRoute->>VLLM: Forward request
    VLLM->>VLLM: CACHE MISS<br/>Process from scratch<br/>XLA compilation
    VLLM-->>Client: Response (215ms)

    Note over Client,VLLM: Request 2: "Translate to French: Goodbye"
    Client->>Gateway: POST /v1/completions
    Gateway->>HTTPRoute: Route by path
    HTTPRoute->>VLLM: Forward to SAME replica
    VLLM->>VLLM: CACHE HIT ✓<br/>Reuse cached prefix
    VLLM-->>Client: Response (82ms - 62% faster)
```

**Key Points:**
- 🔵 **Blue boxes** - Your workload namespace (you manage this)
- 🟡 **Yellow boxes** - Operator namespaces (automatically managed)
- Single replica guarantees all requests hit the same cache
- No EPP scheduler needed (blocked by ALPN bug)
- No EnvoyFilters needed (single replica = no routing decisions)

### Components

**Single vLLM Replica:**
- Runs on dedicated TPU node (4 chips)
- Prefix caching enabled
- Handles all inference requests

**Basic Routing:**
- HTTPRoute for path-based routing only
- No cache-aware routing needed (single replica)
- Simpler configuration than multi-replica

**Security:**
- mTLS encryption for service-to-service communication (automatic)
- HTTPS with KServe-issued TLS certificates for vLLM endpoints (automatic)

### Cache Benefits

**What You'll See:**
- First request with new prefix: ~215ms (cache miss)
- Subsequent requests with same prefix: ~82ms (cache hit)
- **60-75% latency reduction** on repeated prefixes

**Real-World Impact:**
- Translation workloads (repeated instructions)
- Q&A systems (common system prompts)
- Summarization tasks (standard templates)

---

## Optional: Environment Setup

To avoid repeating `--project`, `--zone`, etc. in every command:

```bash
# One-time setup
cp .envrc.example .envrc
# Edit .envrc with your project ID and zone

# Option A: Install direnv (automatic loading)
# See: https://direnv.net
direnv allow .

# Option B: Manual sourcing (no dependencies)
cp env.sh.example env.sh
# Edit env.sh
source env.sh
```

After setup, you can run commands without flags:
```bash
./scripts/preflight-check.sh --tpu
# Shorthand for: ./scripts/preflight-check.sh --accelerator tpu
# Zone defaults to europe-west4-a for TPU deployments
```

**See:** [Environment Setup Guide](../../../docs/environment-setup.md) for complete instructions.

---

## Step 1: Run Validation Checks (3 minutes)

Validate your environment before creating resources:

```bash
# Navigate to repository root
cd /path/to/rhaii-on-xks-gke

# Run preflight check with customer-friendly output (shorthand)
./scripts/preflight-check.sh --tpu --customer

# Zone defaults to europe-west4-a (primary recommended zone for TPU v6e)
# To use a different zone: ./scripts/preflight-check.sh --tpu --zone us-south1-a --customer
```

**Success criteria:**
- ✅ All tools installed (gcloud, kubectl, jq)
- ✅ GCP authentication valid
- ✅ Required permissions granted
- ✅ Secrets exist (pull-secret, huggingface-token)
- ✅ TPU v6e quota: 4 chips available

**If checks fail:** See troubleshooting output for specific fixes.

---

## Step 2: Create GKE Cluster with Single-Node TPU Pool (20 minutes)

Create a GKE cluster with single-node TPU v6e pool for demo:

```bash
# Interactive cluster creation (recommended)
./scripts/create-gke-cluster.sh --tpu --num-nodes 1

# Or specify options explicitly
./scripts/create-gke-cluster.sh --tpu \
  --project YOUR_PROJECT \
  --zone europe-west4-a \
  --cluster-name rhaii-tpu-demo-cluster \
  --num-nodes 1
```

**What this does:**
1. Validates accelerator availability in zone
2. Checks node pool prerequisites and quota (4 chips)
3. Creates GKE cluster (control plane + standard nodes)
4. Creates TPU v6e node pool with **1 node** (ct6e-standard-4t, 4 chips)
5. Configures kubectl access

**Success criteria:**
- ✅ Cluster status: RUNNING
- ✅ TPU node pool created with 1 node
- ✅ kubectl can list nodes (should see 1 TPU node)

**Time:** ~20 minutes (5 min control plane + 15 min TPU node)

**Verify node:**
```bash
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice
```

Expected output:
```
NAME                                         STATUS   ROLES    AGE   VERSION
gke-cluster-tpu-pool-xxxxx                   Ready    <none>   5m    v1.XX.X
```

**Recommended zones for TPU v6e:**
- `europe-west4-a` (primary - most reliable)
- `us-south1-a` (alternative)
- `us-east5-a` (alternative)
- `us-central1-b` (alternative)

---

## Namespace Architecture

Your deployment spans multiple namespaces:

| Namespace | Purpose | Components | Managed By |
|-----------|---------|------------|------------|
| `cert-manager` | Certificate management | cert-manager operator | RHAII on XKS |
| `istio-system` | Service mesh | Istio control plane | RHAII on XKS |
| `opendatahub` | Inference platform | KServe controller, Inference Gateway | RHAII on XKS |
| `openshift-lws-operator` | Workload controller | LeaderWorkerSet controller | RHAII on XKS |
| `rhaii-inference` | Your workload | vLLM pods, HTTPRoute, secrets | **You** |

**Note:** You only manage `rhaii-inference` namespace. Operators manage themselves.

---

## Step 3: Create Namespace and Secrets (2 minutes)

Create the workload namespace and deploy secrets.

**Don't have the secret files yet?** Create them from the included templates:
```bash
cp templates/redhat-pull.yaml.template redhat-pull-secret.yaml
cp templates/huggingface-token.yaml.template huggingface-token-secret.yaml
# Edit each file and replace placeholders with your credentials
```
See [Prerequisites — Required Secrets](../../../docs/prerequisites.md#required-secrets) for details.

```bash
# Create workload namespace with Istio sidecar injection enabled
kubectl apply -f deployments/istio-kserve/simple-caching-demo/namespace-rhaii-inference.yaml

# Set as default namespace for kubectl
kubectl config set-context --current --namespace=rhaii-inference

# Apply Red Hat registry pull secret to workload namespace
kubectl apply -n rhaii-inference -f redhat-pull-secret.yaml

# Apply Red Hat registry pull secret to kube-system (needed for Istio CNI DaemonSet)
kubectl apply -n kube-system -f redhat-pull-secret.yaml

# Apply HuggingFace token secret
kubectl apply -n rhaii-inference -f huggingface-token-secret.yaml

# Verify namespace has Istio injection enabled and secrets created
kubectl get namespace rhaii-inference --show-labels
kubectl get secret rhaiis-pull-secret -n rhaii-inference
kubectl get secret rhaiis-pull-secret -n kube-system
kubectl get secret huggingface-token
```

**Success criteria:**
- ✅ Namespace created with `istio-injection: enabled` label
- ✅ `rhaiis-pull-secret` exists in `rhaii-inference` namespace
- ✅ `rhaiis-pull-secret` exists in `kube-system` namespace (for Istio CNI)
- ✅ `huggingface-token` secret exists in `rhaii-inference` namespace
- ✅ No errors during kubectl apply

**Note:** The `istio-injection: enabled` label automatically injects Istio sidecars into all pods deployed in this namespace. This enables end-to-end mTLS encryption and uniform observability. The pull secret in `kube-system` allows the Istio CNI DaemonSet to pull images from Red Hat registry.

---

## Step 4: Install Operators via [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) (10 minutes)

**Follow the installation instructions in the official repository:**

🔗 **https://github.com/opendatahub-io/rhaii-on-xks**

The repository provides automated installation for:
- cert-manager (certificate management)
- Red Hat OpenShift Service Mesh (Istio)
- KServe v0.15 (inference serving)
- LeaderWorkerSet (LWS) controller

**After installation, verify from rhaii-on-xks-gke repository:**
```bash
cd /path/to/rhaii-on-xks-gke
./scripts/verify-deployment.sh --operators-only
```

**Success criteria:**
- ✅ All operator pods Running
- ✅ cert-manager webhook ready
- ✅ Istio control plane ready
- ✅ KServe controller ready

**Time:** ~10 minutes

**Troubleshooting:** See [Operator Installation Guide](../../../docs/operator-installation.md)

---

## Step 4.1: Configure Istio CNI (3 minutes)

**Why needed:** GKE containers don't include iptables binaries. Istio CNI bypasses this requirement by handling traffic redirection at the CNI plugin level instead of using init containers.

**Configure Istio to use CNI:**

```bash
# 1. Deploy Istio CNI plugin
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/istio-cni.yaml

# 2. Patch istio-cni service account with pull secret (required to pull Red Hat registry image)
kubectl patch serviceaccount istio-cni -n kube-system \
  -p '{"imagePullSecrets": [{"name": "rhaiis-pull-secret"}]}'

# 3. Restart CNI daemonset to pick up pull secret
kubectl rollout restart daemonset istio-cni-node -n kube-system

# 4. Wait for CNI daemonset pods to be ready
kubectl wait --for=condition=Ready pods -l k8s-app=istio-cni-node -n kube-system --timeout=120s

# 5. Configure Istio control plane to use CNI
kubectl patch istio default -n istio-system --type=merge -p '
{
  "spec": {
    "values": {
      "pilot": {
        "cni": {
          "enabled": true
        }
      }
    }
  }
}'

# 6. Restart istiod to apply CNI configuration
kubectl rollout restart deployment/istiod -n istio-system
kubectl rollout status deployment/istiod -n istio-system --timeout=120s

# 7. Verify CNI is enabled
kubectl get configmap istio-sidecar-injector -n istio-system -o jsonpath='{.data.values}' | jq '.pilot.cni'
# Should show: { "enabled": true, "provider": "default" }
```

**What this does:**
- Deploys istio-cni-node daemonset to all nodes (handles iptables setup)
- Configures Istio sidecar injector to skip istio-init container
- Eliminates iptables dependency in application pods
- Enables CNI-based traffic redirection (more secure, no privileged init containers)

**Success criteria:**
- ✅ istio-cni-node daemonset pods Running (check with `kubectl get pods -n kube-system -l k8s-app=istio-cni-node`)
- ✅ Istio CNI configured: `kubectl get configmap istio-sidecar-injector -n istio-system -o jsonpath='{.data.values}' | jq '.pilot.cni.enabled'` shows `true`
- ✅ istiod restarted successfully

**Time:** ~3 minutes

**Troubleshooting:** See [Istio CNI Configuration](../../../docs/operator-installation.md#istio-cni-configuration)

---

## Step 5: Deploy Inference Service (10 minutes)

Deploy the single-replica vLLM inference service with prefix caching:

```bash
# From repository root
kubectl apply -f deployments/istio-kserve/simple-caching-demo/llmisvc-tpu-single-replica.yaml
```

**What this creates:**
- LLMInferenceService custom resource (declares intent)
- InferencePool (backend routing - auto-created by KServe)
- Service (Kubernetes service - auto-created by KServe)
- Pod with vLLM container (workload)

**Monitor deployment:**
```bash
# Watch LLMInferenceService status
kubectl get llminferenceservice -n rhaii-inference -w

# Watch pod status
kubectl get pods -n rhaii-inference -l serving.kserve.io/inferenceservice=qwen-3b-tpu-svc -w
```

**Success criteria:**
- ✅ LLMInferenceService shows READY=True
- ✅ Pod status: Running with 3/3 containers ready
- ✅ InferencePool created automatically

**Time:** ~5 minutes (TPU initialization + model download + XLA compilation)

**Expected output:**
```bash
kubectl get llminferenceservice -n rhaii-inference
```

```
NAME              READY   URL                                                      AGE
qwen-3b-tpu-svc   True    https://inference-gateway.opendatahub/rhaii-inference/qwen-3b-tpu-svc   5m
```

**Verify pod status:**
```bash
kubectl get pods -n rhaii-inference
```

```
NAME                  READY   STATUS    RESTARTS   AGE
qwen-3b-tpu-svc-0-0   3/3     Running   0          5m
```

**Container breakdown:**
- `istio-proxy` - Istio sidecar for mTLS
- `main` - vLLM inference container
- `queue-proxy` - KServe request queue manager

---

## Step 6: Apply Routing Configuration (2 minutes)

Configure HTTP routing for the inference service.

**Single-replica deployment:** No EnvoyFilters needed since all requests naturally route to the same pod. Only HTTPRoute is required for path-based routing.

```bash
# From repository root
kubectl apply -f deployments/istio-kserve/simple-caching-demo/httproute-health-models.yaml
```

**What this does:**
- Routes `/rhaii-inference/qwen-3b-tpu-svc/health` → vLLM health endpoint
- Routes `/rhaii-inference/qwen-3b-tpu-svc/v1/models` → vLLM models endpoint
- Routes `/rhaii-inference/qwen-3b-tpu-svc/*` → all other vLLM endpoints (inference)

**Note:** Unlike the 3-replica production deployment, this demo does NOT deploy EnvoyFilters for cache-aware routing. Single replica means all requests naturally hit the same cache.

**Verify HTTPRoute:**
```bash
kubectl get httproute -n rhaii-inference
```

Expected output:
```
NAME                        HOSTNAMES   AGE
qwen-3b-tpu-svc             ["*"]       30s
```

**Verify Gateway binding:**
```bash
kubectl describe httproute qwen-3b-tpu-svc -n rhaii-inference | grep -A5 "Parent Refs"
```

Expected output shows binding to `inference-gateway` in `opendatahub` namespace.

**Success criteria:**
- ✅ HTTPRoute created
- ✅ HTTPRoute bound to Gateway
- ✅ No errors during apply

**Note:** Step 7 (NetworkPolicies) is skipped in this single-replica demo for simplicity.

---

## Step 8: Verify Deployment (5 minutes)

Run automated verification to confirm deployment health:

```bash
# From repository root
./scripts/verify-deployment.sh
```

**What this checks:**
- ✅ Operators running (cert-manager, Istio, KServe, LWS)
- ✅ Inference Gateway has external IP
- ✅ LLMInferenceService ready
- ✅ Pods running with correct container count
- ✅ InferencePool configured
- ✅ HTTPRoute created

**Success criteria:**
All checks pass with green checkmarks.

**If verification fails:** See troubleshooting section below for common issues and solutions.

**Manual verification:**

```bash
# Get Gateway external IP
GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')
echo "Gateway IP: $GATEWAY_IP"

# Test health endpoint
curl -k https://$GATEWAY_IP/rhaii-inference/qwen-3b-tpu-svc/health
```

Expected output:
```json
{"status":"ok"}
```

**Test model listing:**
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
      "owned_by": "vllm",
      "created": 1234567890
    }
  ]
}
```

---

## Step 9: Performance Validation with Cache Test (2 minutes)

Run the cache routing test to verify prefix caching effectiveness:

```bash
# From repository root
./scripts/test-cache-routing.sh
```

**What this does:**
1. Gets Gateway IP automatically
2. Sends 10 sequential requests with same prefix
3. Measures latency for each request
4. Calculates cache speedup percentage

**Expected output:**

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

**Success criteria:**
- ✅ First request: ~200-230ms (cache miss - XLA compilation)
- ✅ Subsequent requests: ~80-90ms (cache hits)
- ✅ Average speedup: 60-75%

**Why single replica guarantees cache hits:**
- Only one vLLM instance exists
- All requests route to same pod
- Cached prefixes always available
- No routing needed (unlike multi-replica with EPP scheduler)

---

## Step 10: Verify Model Configuration and Cache Behavior (2 minutes)

Manually verify vLLM configuration and cache metrics:

### Check vLLM Configuration

```bash
# Get pod name
POD_NAME=$(kubectl get pods -n rhaii-inference -l serving.kserve.io/inferenceservice=qwen-3b-tpu-svc -o jsonpath='{.items[0].metadata.name}')

# Check vLLM startup arguments
kubectl logs $POD_NAME -n rhaii-inference -c main | grep "vllm.entrypoints.openai.api_server"
```

**Expected configuration:**
```
--model=/mnt/models
--dtype=half
--max-model-len=2048
--tensor-parallel-size=4
--enable-prefix-caching     # ← Confirms prefix caching enabled
--max-num-seqs=128
--ssl-certfile=/var/run/kserve/tls/tls.crt
--ssl-keyfile=/var/run/kserve/tls/tls.key
```

### Check vLLM Cache Metrics

```bash
# Query vLLM metrics endpoint
kubectl exec $POD_NAME -n rhaii-inference -c main -- \
  curl -sk https://localhost:8000/metrics | grep prefix_cache
```

**Expected output (after running test-cache-routing.sh):**
```
# HELP vllm:prefix_cache_queries_total Total number of prefix cache queries
# TYPE vllm:prefix_cache_queries_total counter
vllm:prefix_cache_queries_total 10.0

# HELP vllm:prefix_cache_hits_total Total number of prefix cache hits
# TYPE vllm:prefix_cache_hits_total counter
vllm:prefix_cache_hits_total 9.0    # 90% cache hit rate (9 hits / 10 requests)

# HELP vllm:prefix_cache_misses_total Total number of prefix cache misses
# TYPE vllm:prefix_cache_misses_total counter
vllm:prefix_cache_misses_total 1.0  # First request was cache miss
```

**Key metrics:**
- `prefix_cache_queries_total`: Total requests processed
- `prefix_cache_hits_total`: Requests served from cache
- `prefix_cache_misses_total`: Requests requiring full computation
- **Cache hit rate**: `hits / queries` (should be ~90% after test)

### Verify TPU Topology

```bash
# Check TPU environment variables
kubectl exec $POD_NAME -n rhaii-inference -c main -- env | grep TPU
```

Expected output:
```
TPU_CHIPS_PER_HOST_BOUNDS=2,2,1  # 2x2 topology for 4 chips
TPU_HOST_BOUNDS=1,1,1            # Single host
PJRT_DEVICE=TPU                  # TPU backend
TPU_NUM_DEVICES=4                # 4 chips total
```

---

## 🎉 Success!

Your RHAII TPU demo deployment is ready to test!

### Quick Reference

**Inference Endpoint:**
```bash
# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')

# Test inference
curl -k -X POST https://$GATEWAY_IP/rhaii-inference/qwen-3b-tpu-svc/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/mnt/models",
    "prompt": "What is the capital of France?",
    "max_tokens": 50
  }'
```

**OpenAI-Compatible API:**
- POST `/rhaii-inference/qwen-3b-tpu-svc/v1/completions` - Text completion
- POST `/rhaii-inference/qwen-3b-tpu-svc/v1/chat/completions` - Chat completion
- GET `/rhaii-inference/qwen-3b-tpu-svc/v1/models` - List models
- GET `/rhaii-inference/qwen-3b-tpu-svc/health` - Health check

**Monitor Deployment:**
```bash
# Check pod status
kubectl get pods -n rhaii-inference

# View logs
kubectl logs -f $POD_NAME -c main -n rhaii-inference

# Check resource usage
kubectl top nodes
kubectl top pods -n rhaii-inference
```

**Performance Summary:**
- **First request (cache miss):** ~215ms
- **Cached requests (cache hit):** ~82ms
- **Cache speedup:** 62%
- **Parallel throughput:** ~8.3 req/s
- **Serial throughput:** ~2.1 req/s

---

## Operational Procedures

### Scale Replicas (Upgrade to Multi-Replica)

**Note:** Multi-replica deployment requires fixing the EPP scheduler ALPN bug first. See `docs/BUG-EPP-Scheduler-ALPN.md` for details.

**To scale from 1 to 3 replicas (when EPP is fixed):**

1. **Edit manifest:**
```yaml
# In llmisvc-tpu-single-replica.yaml
spec:
  replicas: 3  # Scale to 3 replicas
```

2. **Scale node pool:**
```bash
gcloud container clusters resize rhaii-tpu-demo-cluster \
  --node-pool tpu-pool \
  --num-nodes 3 \
  --zone europe-west4-a
```

3. **Apply changes:**
```bash
kubectl apply -f deployments/istio-kserve/simple-caching-demo/llmisvc-tpu-single-replica.yaml
```

4. **Deploy EnvoyFilters (required for 3-replica):**
```bash
# Use production manifests with cache-aware routing
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/envoyfilter-ext-proc-body-forward.yaml
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/envoyfilter-load-balancer-policy.yaml
```

**See:** Production deployment guides ([deployment-tpu.md](../../../docs/deployment-tpu.md)) for complete multi-replica setup.

### Rolling Updates

**Update vLLM version:**
```yaml
# Edit llmisvc-tpu-single-replica.yaml
spec:
  template:
    containers:
    - image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.3.0  # New version
```

```bash
kubectl apply -f deployments/istio-kserve/simple-caching-demo/llmisvc-tpu-single-replica.yaml
```

**Update model:**
```yaml
# Edit llmisvc-tpu-single-replica.yaml
spec:
  model:
    uri: hf://meta-llama/Llama-3.1-8B-Instruct  # Different model
    name: meta-llama/Llama-3.1-8B-Instruct
```

```bash
kubectl apply -f deployments/istio-kserve/simple-caching-demo/llmisvc-tpu-single-replica.yaml
```

**Note:** Rolling updates with single replica cause brief downtime (~5 min). For zero-downtime updates, use multi-replica deployment.

---

## Scale to Zero (Cost Savings)

When not testing, scale to zero to avoid charges:

```bash
# Scale node pool to zero
gcloud container clusters resize rhaii-tpu-demo-cluster \
  --node-pool tpu-pool \
  --num-nodes 0 \
  --zone europe-west4-a
```

**Note:** Always use explicit `gcloud container clusters resize` for TPU pools. Autoscaling is unreliable with TPU topology constraints.

### Scale Back Up

```bash
# Restore 1-node pool
gcloud container clusters resize rhaii-tpu-demo-cluster \
  --node-pool tpu-pool \
  --num-nodes 1 \
  --zone europe-west4-a

# Wait for node ready (~10 minutes)
kubectl get nodes -w

# Pods will automatically restart once node is ready
kubectl get pods -n rhaii-inference -w
```

---

## Troubleshooting

### Pod Not Starting

**Symptoms:**
- Pod stuck in Pending or ContainerCreating
- LLMInferenceService shows READY=False

**Diagnose:**
```bash
# Check pod status
kubectl describe pod $POD_NAME -n rhaii-inference

# Check events
kubectl get events -n rhaii-inference --sort-by='.lastTimestamp'
```

**Common causes and solutions:**

#### ImagePullBackOff
```bash
# Verify pull secret exists
kubectl get secret rhaiis-pull-secret -n rhaii-inference

# Re-create if missing
kubectl create secret generic rhaiis-pull-secret \
  --from-file=.dockerconfigjson=./redhat-pull-secret.yaml \
  --type=kubernetes.io/dockerconfigjson \
  -n rhaii-inference
```

#### TPU Not Available
```bash
# Check TPU node exists
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice

# If no nodes, check node pool
gcloud container node-pools describe tpu-pool \
  --cluster rhaii-tpu-demo-cluster \
  --zone europe-west4-a

# Scale up if needed
gcloud container clusters resize rhaii-tpu-demo-cluster \
  --node-pool tpu-pool \
  --num-nodes 1 \
  --zone europe-west4-a
```

#### Pod Initialization Failed (Istio CNI)
```bash
# Error: "Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network"
# Solution: Verify Istio CNI configuration (Step 5.1)

# Check CNI configuration
kubectl get configmap istio-cni-config -n istio-system -o yaml | grep cni_bin_dir

# Should show: "cni_bin_dir": "/home/kubernetes/bin"
# If not, re-apply CNI patch from Step 5.1
```

---

### No External IP on Gateway

**Symptoms:**
- `kubectl get gateway` shows no external IP
- Cannot access inference endpoints

**Solution:**

Wait 2-3 minutes for GCP Load Balancer provisioning:

```bash
kubectl get gateway inference-gateway -n opendatahub -w
```

Expected progression:
```
NAME                 CLASS    ADDRESS         READY   AGE
inference-gateway    istio    <pending>       True    30s
inference-gateway    istio    34.123.45.67    True    2m30s
```

**If still pending after 5 minutes:**

```bash
# Check Gateway status
kubectl describe gateway inference-gateway -n opendatahub

# Check Istio logs
kubectl logs -n istio-system -l app=istiod

# Verify GCP quota for forwarding rules
gcloud compute forwarding-rules list --project=YOUR_PROJECT
```

---

### Inference Requests Failing

**Symptoms:**
- HTTP 404 Not Found
- HTTP 503 Service Unavailable
- Connection refused

**Diagnose:**

```bash
# Test Gateway IP is reachable
GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')
ping $GATEWAY_IP

# Test health endpoint
curl -k https://$GATEWAY_IP/rhaii-inference/qwen-3b-tpu-svc/health

# Check HTTPRoute configuration
kubectl get httproute qwen-3b-tpu-svc -n rhaii-inference -o yaml
```

**Common causes:**

#### Wrong URL Path
```bash
# ❌ Wrong (missing namespace prefix)
curl https://$GATEWAY_IP/v1/models

# ✅ Correct (includes namespace and service name)
curl -k https://$GATEWAY_IP/rhaii-inference/qwen-3b-tpu-svc/v1/models
```

#### Pod Not Ready
```bash
# Check pod readiness
kubectl get pods -n rhaii-inference

# If not ready, check logs
kubectl logs $POD_NAME -n rhaii-inference -c main
```

#### HTTPRoute Not Applied
```bash
# Verify HTTPRoute exists
kubectl get httproute -n rhaii-inference

# Re-apply if missing
kubectl apply -f deployments/istio-kserve/simple-caching-demo/httproute-health-models.yaml
```

---

### Low or No Cache Speedup

**Symptoms:**
- All requests show similar latency
- No ~60% speedup on cached requests

**Diagnose:**

```bash
# Check vLLM cache metrics
kubectl exec $POD_NAME -n rhaii-inference -c main -- \
  curl -sk https://localhost:8000/metrics | grep prefix_cache
```

**Expected vs. Problem:**
```
# ✅ Good: 90% hit rate
vllm:prefix_cache_hits_total 9.0
vllm:prefix_cache_queries_total 10.0

# ❌ Problem: 0% hit rate
vllm:prefix_cache_hits_total 0.0
vllm:prefix_cache_queries_total 10.0
```

**Common causes:**

#### Prefix Caching Not Enabled
```bash
# Check vLLM startup args
kubectl logs $POD_NAME -n rhaii-inference -c main | grep enable-prefix-caching

# Should show: --enable-prefix-caching
# If missing, verify manifest has this arg
```

#### Test Prompt Too Short
```bash
# EPP scheduler uses 64-token block size
# Use test script with default 100+ token prompt
./scripts/test-cache-routing.sh

# Or use longer custom prompt:
curl -k -X POST https://$GATEWAY_IP/rhaii-inference/qwen-3b-tpu-svc/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/mnt/models",
    "prompt": "You are a helpful AI assistant. Please provide a comprehensive analysis of the following topic: What is machine learning?",
    "max_tokens": 50
  }'
```

#### Different Prompts (No Shared Prefix)
```bash
# ❌ These don't share prefix:
Prompt 1: "What is 2+2?"
Prompt 2: "Translate to French: Hello"

# ✅ These share prefix:
Prompt 1: "You are a helpful AI. What is 2+2?"
Prompt 2: "You are a helpful AI. What is 5+5?"
```

---

### vLLM Container Crash or Restart

**Symptoms:**
- Pod shows CrashLoopBackOff
- Container restarts repeatedly

**Diagnose:**

```bash
# Check pod logs
kubectl logs $POD_NAME -n rhaii-inference -c main

# Check previous container logs if restarted
kubectl logs $POD_NAME -n rhaii-inference -c main --previous
```

**Common causes:**

#### Out of Memory (OOM)
```
Error: CUDA out of memory
```

**Solution:** Model too large for TPU v6e with 4 chips. Try smaller model:
```yaml
spec:
  model:
    uri: hf://google/gemma-2b-it  # Smaller model
```

#### Model Download Failed
```
Error: 401 Unauthorized (HuggingFace)
```

**Solution:** Verify HuggingFace token has access to gated models:
```bash
# Test token
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://huggingface.co/api/models/Qwen/Qwen2.5-3B-Instruct

# Re-create secret if invalid
kubectl delete secret huggingface-token -n rhaii-inference
kubectl create secret generic huggingface-token \
  --from-literal=token=YOUR_VALID_TOKEN \
  -n rhaii-inference

# Restart pod
kubectl delete pod $POD_NAME -n rhaii-inference
```

#### XLA Compilation Timeout
```
Error: TPU initialization timed out
```

**Solution:** Increase readiness probe delay:
```yaml
# In llmisvc-tpu-single-replica.yaml
readinessProbe:
  initialDelaySeconds: 360  # Increase from 240s to 360s
```

---

### Gateway Returns 404 for All Paths

**Symptoms:**
- All requests return HTTP 404 Not Found
- Health endpoint also 404

**Diagnose:**

```bash
# Check HTTPRoute parent refs
kubectl describe httproute qwen-3b-tpu-svc -n rhaii-inference

# Should show:
#   Parent Refs:
#     Name: inference-gateway
#     Namespace: opendatahub
```

**Solution:**

Verify Gateway exists and HTTPRoute binds correctly:

```bash
# Check Gateway
kubectl get gateway inference-gateway -n opendatahub

# Re-apply HTTPRoute if binding missing
kubectl delete httproute qwen-3b-tpu-svc -n rhaii-inference
kubectl apply -f deployments/istio-kserve/simple-caching-demo/httproute-health-models.yaml

# Wait 30s for routing to propagate
sleep 30

# Test again
curl -k https://$GATEWAY_IP/rhaii-inference/qwen-3b-tpu-svc/health
```

---

## Complete Teardown

When finished testing, clean up all resources:

### Option 1: Delete Entire Cluster (Recommended)

```bash
# Delete cluster (removes everything)
gcloud container clusters delete rhaii-tpu-demo-cluster \
  --zone europe-west4-a \
  --quiet
```

**Time:** ~5 minutes

**Cost:** $0 after deletion

---

### Option 2: Delete Workload Only (Keep Cluster)

```bash
# Delete LLMInferenceService
kubectl delete llminferenceservice qwen-3b-tpu-svc -n rhaii-inference

# Delete HTTPRoute
kubectl delete httproute qwen-3b-tpu-svc -n rhaii-inference

# Delete namespace
kubectl delete namespace rhaii-inference

# Scale node pool to zero
gcloud container clusters resize rhaii-tpu-demo-cluster \
  --node-pool tpu-pool \
  --num-nodes 0 \
  --zone europe-west4-a
```

**Note:** Standard pool (control plane) still incurs charges (~$2/day).

---

## Reference

### Manifest Files

All manifests in `deployments/istio-kserve/simple-caching-demo/`:

- `namespace-rhaii-inference.yaml` - Namespace with Istio injection
- `llmisvc-tpu-single-replica.yaml` - Single-replica TPU deployment
- `httproute-health-models.yaml` - HTTPRoute for basic routing

### Performance Metrics

**Single-replica TPU v6e performance:**

| Metric | Value |
|--------|-------|
| Parallel throughput | ~8.3 req/s |
| Serial throughput | ~2.1 req/s |
| First request (cache miss) | ~215ms |
| Cached request (cache hit) | ~82ms |
| Cache speedup | 62% |
| Cost | ~$15/day (1 node) |

**Comparison to 3-replica production deployment:**

| Metric | Single-replica (Demo) | 3-replica (Production) |
|--------|----------------------|------------------------|
| Throughput | ~8.3 req/s | ~25 req/s |
| Cache speedup | 62% | 62% (same) |
| Latency (cached) | 82ms | 82ms (same) |
| Cost | ~$15/day | ~$46/day |
| Nodes | 1 TPU node | 3 TPU nodes |
| Complexity | Simple (no EPP) | Advanced (EPP + EnvoyFilters) |

### Recommended Zones

**TPU v6e availability:**

| Zone | Status | Notes |
|------|--------|-------|
| `europe-west4-a` | ✅ Primary | Most reliable |
| `us-south1-a` | ✅ Alternative | Good availability |
| `us-east5-a` | ✅ Alternative | Good availability |
| `us-central1-b` | ✅ Alternative | Good availability |

**Check real-time availability:**
```bash
./scripts/check-accelerator-availability.sh --customer --zone europe-west4-a --type tpu
```

### vLLM Configuration

**TPU-specific args:**
- `--dtype=half` - FP16 precision (required for TPU)
- `--max-model-len=2048` - Context window (adjust for model size vs memory)
- `--tensor-parallel-size=4` - Use all 4 TPU chips
- `--enable-prefix-caching` - Enable prefix caching
- `--max-num-seqs=128` - Max concurrent sequences (adjust for workload)

**TPU environment variables:**
- `TPU_CHIPS_PER_HOST_BOUNDS=2,2,1` - 2x2 topology for 4 chips
- `TPU_HOST_BOUNDS=1,1,1` - Single host
- `PJRT_DEVICE=TPU` - Use TPU backend

### External References

- **RHAII on XKS Repository:** https://github.com/opendatahub-io/rhaii-on-xks
- **vLLM Prefix Caching Docs:** https://docs.vllm.ai/en/latest/features/prefix_caching.html
- **KServe Documentation:** https://kserve.github.io/website/
- **Istio Documentation:** https://istio.io/latest/docs/
- **EPP Scheduler ALPN Bug:** `docs/BUG-EPP-Scheduler-ALPN.md` in this repository

---

**Need help?** See:
- [Prerequisites Guide](../../../docs/prerequisites.md)
- [Operator Installation](../../../docs/operator-installation.md)
- [Verification and Testing](../../../docs/verification-testing.md)
- [Troubleshooting Guide](../../../docs/troubleshooting.md)
- [FAQ](../../../docs/faq.md)
