# RHAII on GKE - Customer Deployment Repository

Production-ready deployment guides and automation for **Red Hat AI Inference Services (RHAII)** vLLM workloads on Google Kubernetes Engine (GKE).

## 🚀 Quick Start

**New to RHAII on GKE?** Start here:

### 30-Minute Deployment Guides

Choose your accelerator:

- **[TPU Quickstart](docs/customer-guides/quickstart-tpu.md)** - Deploy on TPU v6e (~$132/day)
- **[GPU Quickstart](docs/customer-guides/quickstart-gpu.md)** - Deploy on GPU T4 (~$80/day)

Both guides take you from zero to deployed in 30-40 minutes.

---

## 📖 Documentation

### Getting Started
- **[Prerequisites](docs/customer-guides/prerequisites.md)** - Everything you need before deploying
- **[Operator Installation](docs/customer-guides/operator-installation.md)** - Install RHAII operators via [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks)

### Deployment Guides

**Single-Model Deployments** (Development, <10 req/s):
- [Single-Model TPU](docs/customer-guides/single-model-deployment-tpu.md) - Baseline TPU deployment
- [Single-Model GPU](docs/customer-guides/single-model-deployment-gpu.md) - Baseline GPU deployment

**High-Throughput Scale-Out** (Production, >10 req/s):
- [Scale-Out TPU](docs/customer-guides/scale-out-deployment-tpu.md) - 3-replica deployment with prefix caching
- [Scale-Out GPU](docs/customer-guides/scale-out-deployment-gpu.md) - 3-replica GPU deployment

### Operations
- [Verification & Testing](docs/customer-guides/verification-testing.md) - Validate your deployment
- [Production Hardening](docs/customer-guides/production-hardening.md) - Security and reliability
- [Cost Management](docs/customer-guides/cost-management.md) - Optimize and control costs
- [Troubleshooting](docs/customer-guides/troubleshooting.md) - Common issues and solutions
- [FAQ](docs/customer-guides/faq.md) - Frequently asked questions

**Complete Index:** [Customer Guides Hub](docs/customer-guides/README.md)

---

## 🛠️ Automation Scripts

All deployment guides use these automation scripts in `scripts/`:

### Validation Scripts
- `preflight-check.sh` - Comprehensive prerequisite validation
- `check-accelerator-availability.sh` - Zone and accelerator validation
- `check-nodepool-prerequisites.sh` - Node pool compatibility and quota checks

### Deployment Scripts
- `create-gke-cluster.sh` - Automated cluster creation with integrated validation
- `verify-deployment.sh` - Post-deployment health checks
- `cost-estimator.sh` - Cost calculation and comparison

**Example:**
```bash
# Run validation
./scripts/preflight-check.sh --customer --deployment istio-kserve/baseline-pattern --accelerator tpu

# Create cluster
./scripts/create-gke-cluster.sh --tpu

# Verify deployment
./scripts/verify-deployment.sh --deployment single-model
```

---

## 🎯 Deployment Decision Guide

### When to use TPU vs GPU?

| Factor | TPU v6e | GPU T4 | Winner |
|--------|---------|--------|--------|
| Performance | ~7-8 req/s | ~5-6 req/s | TPU |
| Cost (single-model) | ~$132/day | ~$80/day | GPU |
| Zone availability | 5 zones | 20+ zones | GPU |
| Best for | Production | PoC/Dev | - |

**Recommendation:** Start with GPU for PoC, upgrade to TPU for production.

### When to use Single-Model vs Scale-Out?

| Factor | Single-Model | Scale-Out (3x) |
|--------|--------------|----------------|
| Traffic | <10 req/s | >10 req/s |
| Cost (TPU) | ~$132/day | ~$377/day |
| Cost (GPU) | ~$80/day | ~$228/day |
| Performance (TPU) | ~7-8 req/s | ~25 req/s |
| Performance (GPU) | ~5-6 req/s | ~18 req/s |
| High Availability | No | Yes |

**Recommendation:** Start with single-model, scale when traffic consistently exceeds 10 req/s.

---

## 💰 Cost Estimates

### Monthly Costs (Running 24/7)

| Deployment | TPU v6e | GPU T4 |
|------------|---------|--------|
| Single-Model | $3,960/mo | $2,400/mo |
| Scale-Out (3x) | $11,310/mo | $6,840/mo |
| **Scaled to Zero** | $180/mo | $180/mo |

**💡 Cost Tip:** Scale node pools to zero when not in use. See [Cost Management](docs/customer-guides/cost-management.md).

---

## 📂 Repository Structure

```
rhaii-on-xks-gke/
├── README.md                          # This file
│
├── docs/customer-guides/              # Customer-facing guides
│   ├── README.md                      # Complete guide index
│   ├── quickstart-tpu.md              # 30-min TPU deployment
│   ├── quickstart-gpu.md              # 30-min GPU deployment
│   ├── prerequisites.md               # Setup requirements
│   ├── operator-installation.md       # RHAII operator installation
│   ├── single-model-deployment-*.md   # Single-model guides
│   ├── scale-out-deployment-*.md      # Scale-out guides
│   ├── verification-testing.md        # Validation procedures
│   ├── production-hardening.md        # Production checklist
│   ├── cost-management.md             # Cost optimization
│   ├── troubleshooting.md             # Common issues
│   └── faq.md                         # FAQ
│
├── scripts/                           # Automation scripts
│   ├── create-gke-cluster.sh          # Cluster creation
│   ├── verify-deployment.sh           # Post-deployment validation
│   ├── cost-estimator.sh              # Cost calculator
│   ├── preflight-check.sh             # Prerequisite validation
│   ├── check-accelerator-availability.sh  # Zone validation
│   └── check-nodepool-prerequisites.sh    # Node pool validation
│
├── deployments/                       # Kubernetes manifests
│   └── istio-kserve/
│       ├── baseline-pattern/         # Single-model deployment
│       │   └── manifests/
│       │       ├── llmisvc-tpu.yaml   # TPU manifest
│       │       ├── llmisvc-gpu.yaml   # GPU manifest
│       │       └── networkpolicies/   # Security policies
│       └── caching-pattern/          # Scale-out deployment
│           └── manifests/
│               ├── llmisvc-tpu-caching.yaml
│               ├── llmisvc-gpu-caching.yaml
│               └── networkpolicies/
│
└── benchmarks/                        # Performance testing
    ├── python/
    └── config/
```

---

## 🔧 Prerequisites

Before deploying, ensure you have:

- ✅ Google Cloud account with billing enabled
- ✅ GCP project with appropriate quotas
- ✅ `gcloud` CLI installed and authenticated
- ✅ `kubectl` CLI installed
- ✅ Red Hat registry credentials (pull secret)
- ✅ HuggingFace token for model access

**Detailed setup:** [Prerequisites Guide](docs/customer-guides/prerequisites.md)

---

## 🚀 Deployment Overview

### Step-by-Step Process

1. **Prerequisites** (15-30 minutes, one-time)
   - Install tools, configure accounts, request quotas

2. **Cluster Creation** (~15 minutes)
   ```bash
   ./scripts/create-gke-cluster.sh --tpu  # or --gpu
   ```

3. **Operator Installation** (~10 minutes)
   - Clone [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) repository
   - Deploy operators (cert-manager, Istio, KServe, LWS)

4. **Deploy Workload** (~10 minutes)
   ```bash
   kubectl apply -f deployments/istio-kserve/baseline-pattern/manifests/llmisvc-tpu.yaml
   ```

5. **Verify & Test** (~3 minutes)
   ```bash
   ./scripts/verify-deployment.sh --deployment single-model
   ```

**Total time:** ~30-40 minutes for complete deployment

---

## 🆘 Getting Help

1. **Check the [FAQ](docs/customer-guides/faq.md)** - Common questions answered
2. **Review [Troubleshooting](docs/customer-guides/troubleshooting.md)** - Solutions to common issues
3. **Run verification:** `./scripts/verify-deployment.sh --operators-only`
4. **Check logs:** `kubectl logs -l serving.kserve.io/inferenceservice`

---

## 📝 License

This repository provides deployment configurations and documentation for Red Hat AI Inference Services (RHAII) on Google Cloud Platform.

**External Dependencies:**
- [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) - Operator installation (required)
- Red Hat AI Inference Services - Commercial product (requires license)

---

## 🔗 Related Resources

- [RHAII on XKS GitHub](https://github.com/opendatahub-io/rhaii-on-xks) - Official operator repository
- [llm-d Documentation](https://llm-d.ai/docs/) - LLM framework architecture
- [GKE AI Labs](https://gke-ai-labs.dev) - Google Cloud AI resources
- [KServe Documentation](https://kserve.github.io/website/) - KServe reference

---

**Ready to deploy?** Start with:
- [TPU Quickstart](docs/customer-guides/quickstart-tpu.md) for maximum performance
- [GPU Quickstart](docs/customer-guides/quickstart-gpu.md) for cost-effective PoC
