# RHAII on GKE - Customer Deployment Repository

Production-ready deployment guides and automation for **Red Hat AI Inference Services (RHAII)** vLLM workloads on Google Kubernetes Engine (GKE).

## 🚀 Get Started

Choose your accelerator and follow the deployment guide:

- **[RHAII Deployment Guide (TPU)](docs/customer-guides/deployment-tpu.md)** - Deploy on TPU v6e (~25 req/s)
- **[RHAII Deployment Guide (GPU)](docs/customer-guides/deployment-gpu.md)** - Deploy on GPU T4 (~18 req/s)

Both guides deploy a 3-replica vLLM inference service with prefix caching and intelligent routing.

---

## 📖 Documentation

### Getting Started
- **[Prerequisites](docs/customer-guides/prerequisites.md)** - Everything you need before deploying
- **[Environment Setup](docs/customer-guides/environment-setup.md)** - Optional: Configure environment variables to streamline commands
- **[Operator Installation](docs/customer-guides/operator-installation.md)** - Install RHAII operators via [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks)

### Deployment Guides
- [RHAII Deployment Guide (TPU)](docs/customer-guides/deployment-tpu.md) - Production TPU v6e deployment
- [RHAII Deployment Guide (GPU)](docs/customer-guides/deployment-gpu.md) - Production GPU T4 deployment

### Operations
- [Verification & Testing](docs/customer-guides/verification-testing.md) - Validate your deployment
- [Production Hardening](docs/customer-guides/production-hardening.md) - Security and reliability
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
- `delete-gke-cluster.sh` - Safe cluster deletion or scale-to-zero
- `verify-deployment.sh` - Post-deployment health checks

**Example:**
```bash
# Run validation
./scripts/preflight-check.sh --customer --deployment istio-kserve/caching-pattern --accelerator tpu

# Create cluster
./scripts/create-gke-cluster.sh --tpu

# Verify deployment
./scripts/verify-deployment.sh --deployment scale-out
```

---

## 📂 Repository Structure

```
rhaii-on-xks-gke/
├── README.md                          # This file
│
├── docs/customer-guides/              # Customer-facing guides
│   ├── README.md                      # Complete guide index
│   ├── deployment-tpu.md              # TPU deployment guide
│   ├── deployment-gpu.md              # GPU deployment guide
│   ├── prerequisites.md               # Setup requirements
│   ├── operator-installation.md       # RHAII operator installation
│   ├── verification-testing.md        # Validation procedures
│   ├── production-hardening.md        # Production checklist
│   ├── troubleshooting.md             # Common issues
│   └── faq.md                         # FAQ
│
├── scripts/                           # Automation scripts
│   ├── create-gke-cluster.sh          # Cluster creation
│   ├── delete-gke-cluster.sh          # Cluster deletion / scale-to-zero
│   ├── verify-deployment.sh           # Post-deployment validation
│   ├── preflight-check.sh             # Prerequisite validation
│   ├── check-accelerator-availability.sh  # Zone validation
│   └── check-nodepool-prerequisites.sh    # Node pool validation
│
├── deployments/                       # Kubernetes manifests
│   └── istio-kserve/
│       ├── baseline-pattern/         # Smoke testing manifests
│       │   └── manifests/
│       └── caching-pattern/          # Customer deployment manifests
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

2. **Cluster Creation** (~20 minutes)
   ```bash
   ./scripts/create-gke-cluster.sh --tpu  # or --gpu
   ```

3. **Operator Installation** (~10 minutes)
   - Clone [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) repository
   - Deploy operators (cert-manager, Istio, KServe, LWS)

4. **Deploy Workload** (~12 minutes)
   ```bash
   kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml
   ```

5. **Verify & Test** (~5 minutes)
   ```bash
   ./scripts/verify-deployment.sh --deployment scale-out
   ```

**Total time:** ~50 minutes for complete deployment

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
- [Deploy on TPU](docs/customer-guides/deployment-tpu.md) for maximum performance
- [Deploy on GPU](docs/customer-guides/deployment-gpu.md) for wider zone availability
