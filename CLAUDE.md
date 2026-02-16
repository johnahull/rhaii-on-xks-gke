# CLAUDE.md

This repository provides production-ready deployment guides and automation for RHAII (Red Hat AI Inference Services) vLLM workloads on Google Kubernetes Engine (GKE).

## Repository Purpose

**Customer-facing deployment repository** for RHAII on GKE with:
- Step-by-step deployment guides
- Automation scripts with validation
- Production-ready Kubernetes manifests
- Cost management and troubleshooting guides

## Quick Reference

**Primary documentation:** `docs/customer-guides/README.md`

**Automation scripts:** `scripts/`

**Deployment manifests:** `deployments/istio-kserve/`

## Tech Stack

**Deployment Platform:**
- Google Kubernetes Engine (GKE)
- Istio service mesh (via Red Hat OpenShift Service Mesh / sail-operator)
- KServe v0.15 (LLMInferenceService CRD for declarative vLLM management)
- LeaderWorkerSet (LWS) controller

**Accelerators:**
- TPU v6e (Trillium) - `ct6e-standard-4t` machine type, 4 chips per node
- GPU T4 - `n1-standard-4` machine type, 1 GPU per node

**Container Images:**
- TPU: `registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.2.5`
- GPU: `registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.0.0`

**Model:** `google/gemma-2b-it` (default in customer manifests)

## Deployment Patterns

**Pattern 1: Single-Model Baseline**
- 1 replica, baseline performance
- TPU: ~7-8 req/s parallel, ~$132/day
- GPU: ~5-6 req/s parallel, ~$80/day
- Use case: Development, testing, <10 req/s traffic

**Pattern 3: High-Throughput Scale-Out (N/S-Caching)**
- 3 replicas with prefix caching enabled
- TPU: ~25 req/s parallel, ~$377/day
- GPU: ~18 req/s parallel, ~$228/day
- Use case: Production, >10 req/s traffic, shared prompts

## Critical Configuration Rules

**All Deployments:**
- Namespace: `default` (customer manifests use default namespace)
- Pull secret: `rhaiis-pull-secret` (customer-provided Red Hat registry credentials)
- HuggingFace token secret: `huggingface-token` with key `token`

**TPU Deployments:**
- MUST use `--version=v2-alpha-tpuv6e` for TPU VMs (not applicable to GKE)
- MUST request all 4 chips: `resources.limits.google.com/tpu: "4"`
- Node selector: `cloud.google.com/gke-tpu-accelerator: tpu-v6e-slice`
- TPU topology: `2x2` (4 chips, single-host)
- Environment: `TPU_CHIPS_PER_HOST_BOUNDS=2,2,1`, `TPU_HOST_BOUNDS=1,1,1`, `PJRT_DEVICE=TPU`

**GPU Deployments:**
- DO NOT install GPU Operator (GKE provides native GPU support)
- Node selector: `cloud.google.com/gke-accelerator: nvidia-tesla-t4`
- Resource request: `resources.limits.nvidia.com/gpu: "1"`

**Pattern 3 (Scale-Out) Specific:**
- Add `--enable-prefix-caching` to vLLM args
- EnvoyFilter for ext_proc body forwarding (enables cache-aware routing)
- NetworkPolicies for security isolation
- HTTPS with KServe-issued TLS certificates (vLLM serves HTTPS in Pattern 3)

## Operator Installation

**Method:** RHAII on XKS repository (https://github.com/opendatahub-io/rhaii-on-xks)

**Required operators:**
1. cert-manager (certificate management)
2. Red Hat OpenShift Service Mesh (Istio)
3. KServe v0.15 (inference serving)
4. LeaderWorkerSet (LWS) controller

**Installation:**
```bash
cd /path/to/rhaii-on-xks
make deploy-all
make status
```

## Automation Scripts

### Validation Scripts

**preflight-check.sh:**
- Validates tools, authentication, permissions, secrets, dependencies
- Use `--customer` flag for user-friendly output
- Example: `./scripts/preflight-check.sh --customer --deployment istio-kserve/baseline-pattern --accelerator tpu`

**check-accelerator-availability.sh:**
- Validates zone supports TPU v6e or GPU T4
- Use `--customer` flag for recommendations
- Example: `./scripts/check-accelerator-availability.sh --customer --zone us-central1-b --type tpu`

**check-nodepool-prerequisites.sh:**
- Validates machine type, accelerator, quota
- Use `--customer` flag for quota guidance
- Example: `./scripts/check-nodepool-prerequisites.sh --customer --zone us-central1-b --machine-type ct6e-standard-4t --tpu-topology 2x2x1`

### Deployment Scripts

**create-gke-cluster.sh:**
- Integrated cluster creation with all validation
- Interactive mode with cost estimates
- Dry-run mode: `--dry-run`
- Example: `./scripts/create-gke-cluster.sh --tpu --zone us-central1-b`

**verify-deployment.sh:**
- Post-deployment health checks
- Operator validation: `--operators-only`
- Deployment validation: `--deployment single-model` or `--deployment scale-out`

**cost-estimator.sh:**
- Cost calculation and comparison
- Example: `./scripts/cost-estimator.sh --deployment single-model --accelerator tpu --compare`

## Cost Estimates (February 2026 Pricing)

**TPU v6e (us-central1-b):**
- Single-model: ~$132/day ($3,960/month)
- Scale-out (3x): ~$377/day ($11,310/month)
- Scaled to zero: ~$6/day (cluster overhead)

**GPU T4 (us-central1-a):**
- Single-model: ~$80/day ($2,400/month)
- Scale-out (3x): ~$228/day ($6,840/month)
- Scaled to zero: ~$6/day (cluster overhead)

## Common Commands

### Cluster Creation
```bash
# TPU cluster
./scripts/create-gke-cluster.sh --tpu --zone us-central1-b

# GPU cluster
./scripts/create-gke-cluster.sh --gpu --zone us-central1-a
```

### Deployment
```bash
# Single-model TPU
kubectl apply -f deployments/istio-kserve/baseline-pattern/manifests/llmisvc-tpu.yaml

# Scale-out GPU
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml
```

### Verification
```bash
# Check operators
./scripts/verify-deployment.sh --operators-only

# Verify deployment
./scripts/verify-deployment.sh --deployment single-model

# Manual checks
kubectl get llminferenceservice
kubectl get pods -l serving.kserve.io/inferenceservice
kubectl get svc istio-ingressgateway -n istio-system
```

### Cost Management
```bash
# Scale to zero (TPU)
gcloud container clusters resize CLUSTER --node-pool tpu-pool --num-nodes 0 --zone ZONE

# Scale to zero (GPU)
gcloud container clusters resize CLUSTER --node-pool gpu-pool --num-nodes 0 --zone ZONE
```

## Documentation Structure

**Customer Guides** (`docs/customer-guides/`):
- Entry points: `quickstart-tpu.md`, `quickstart-gpu.md`
- Deployment: `single-model-deployment-*.md`, `scale-out-deployment-*.md`
- Operations: `verification-testing.md`, `production-hardening.md`, `cost-management.md`
- Support: `troubleshooting.md`, `faq.md`

**Deployment Manifests** (`deployments/istio-kserve/`):
- `baseline-pattern/manifests/` - Single-model manifests (TPU + GPU)
- `caching-pattern/manifests/` - Scale-out manifests (TPU + GPU)
- NetworkPolicies for security isolation

## External Dependencies

**Required:**
- RHAII on XKS repository for operator installation
- Red Hat registry credentials (pull secret)
- HuggingFace token for model downloads

**Clone location:**
RHAII on XKS should be cloned as sibling directory to this repository for easy access.

## Troubleshooting

**Common issues:**
1. **LLMInferenceService not READY:** Check pod logs, pull secret, HuggingFace token
2. **No external IP on Gateway:** Wait 2-3 minutes for load balancer provisioning
3. **TPU/GPU not detected:** Check node selector, tolerations, resource requests
4. **Inference requests failing:** Verify Gateway IP, HTTPRoute, network connectivity

**See:** `docs/customer-guides/troubleshooting.md` for comprehensive solutions

## GCP Resources

**Recommended zones:**
- TPU v6e: `us-central1-b` (primary), `us-south1-a`, `us-east5-a`
- GPU T4: `us-central1-a` (primary), wide availability in us-* zones

**Project:** Customer should create dedicated GCP project

**Quotas needed:**
- Single-model TPU: 4 TPU v6e chips
- Single-model GPU: 1 T4 GPU
- Scale-out TPU: 12 TPU v6e chips (3 nodes)
- Scale-out GPU: 3 T4 GPUs

## Repository Management

**When making changes:**
- Update customer guides if adding new features
- Test automation scripts with dry-run mode
- Validate manifest changes with kubectl dry-run
- Update cost estimates if pricing changes
- Keep manifest references consistent with guides

**File naming:**
- Manifests: `llmisvc-{accelerator}.yaml` or `llmisvc-{accelerator}-pattern3.yaml`
- Guides: Descriptive names (no "Pattern 1/3" terminology in customer docs)
- Scripts: Action-based names with `.sh` extension

## Support

**Documentation:** All customer-facing guides in `docs/customer-guides/`

**Scripts:** All automation in `scripts/` with `--help` flag

**Troubleshooting:** `docs/customer-guides/troubleshooting.md` + `faq.md`
