# Repository Setup Guide

This repository contains everything needed to deploy RHAII on GKE.

## What's Included

### Documentation (14 files, ~124K)
```
docs/customer-guides/
├── README.md                          # Navigation index
├── quickstart-tpu.md                  # 30-min TPU deployment
├── quickstart-gpu.md                  # 30-min GPU deployment
├── prerequisites.md                   # Setup requirements
├── operator-installation.md           # RHAII operator installation
├── single-model-deployment-tpu.md     # Single-model TPU guide
├── single-model-deployment-gpu.md     # Single-model GPU guide
├── scale-out-deployment-tpu.md        # Scale-out TPU guide
├── scale-out-deployment-gpu.md        # Scale-out GPU guide
├── verification-testing.md            # Validation procedures
├── production-hardening.md            # Production checklist
├── cost-management.md                 # Cost optimization
├── troubleshooting.md                 # Common issues
└── faq.md                             # FAQ
```

### Automation Scripts (6 files, ~120K)
```
scripts/
├── create-gke-cluster.sh              # Cluster creation (13K)
├── verify-deployment.sh               # Post-deployment validation (12K)
├── cost-estimator.sh                  # Cost calculator (9K)
├── preflight-check.sh                 # Prerequisite validation (22K)
├── check-accelerator-availability.sh  # Zone validation (25K)
└── check-nodepool-prerequisites.sh    # Node pool validation (28K)
```

### Kubernetes Manifests
```
deployments/istio-kserve/
├── baseline-pattern/manifests/
│   ├── llmisvc-tpu.yaml               # Single-model TPU
│   ├── llmisvc-gpu.yaml               # Single-model GPU (NEW)
│   ├── httproute.yaml                 # HTTP routing
│   └── networkpolicies/               # Security policies
│       ├── allow-gateway.yaml
│       ├── allow-vllm-egress.yaml
│       └── default-deny.yaml
│
└── caching-pattern/manifests/
    ├── llmisvc-tpu-caching.yaml      # Scale-out TPU
    ├── llmisvc-gpu-caching.yaml      # Scale-out GPU (NEW)
    ├── envoyfilter-route-extproc-body.yaml
    └── networkpolicies/               # Security policies
        ├── allow-epp-scheduler.yaml
        ├── allow-gateway-to-vllm.yaml
        ├── allow-vllm-egress.yaml
        └── allow-istio.yaml
```

### Benchmarking Tools
```
benchmarks/
├── python/
│   ├── benchmark_async.py
│   ├── locustfile.py
│   ├── pattern2_benchmark_retry.py
│   └── utils/
└── config/
```

### Repository Files
```
.
├── README.md                          # Main repository README
├── CLAUDE.md                          # Claude Code guidance
├── SETUP.md                           # This file
└── .gitignore                         # Git ignore patterns
```

## Total Files

- **Documentation:** 14 customer guides (124K)
- **Scripts:** 6 automation scripts (120K)
- **Manifests:** 13 Kubernetes YAML files
- **Benchmarks:** Benchmarking tools and utilities
- **Total:** 40+ files ready for customer use

## Getting Started

### For New Users

1. **Read the documentation:**
   ```bash
   cat docs/customer-guides/README.md
   ```

2. **Choose your deployment:**
   - TPU: `docs/customer-guides/quickstart-tpu.md`
   - GPU: `docs/customer-guides/quickstart-gpu.md`

3. **Run validation:**
   ```bash
   ./scripts/preflight-check.sh --customer --deployment istio-kserve/baseline-pattern --accelerator tpu
   ```

### For Developers

1. **Review CLAUDE.md:**
   ```bash
   cat CLAUDE.md
   ```

2. **Test scripts:**
   ```bash
   # Dry run cluster creation
   ./scripts/create-gke-cluster.sh --tpu --dry-run

   # Check accelerator availability
   ./scripts/check-accelerator-availability.sh --customer --type tpu

   # Estimate costs
   ./scripts/cost-estimator.sh --deployment single-model --accelerator tpu
   ```

## Repository Setup for Git

```bash
cd /home/jhull/devel/rhaii-on-xks-gke

# Initialize git repository
git init

# Add files
git add .

# Create initial commit
git commit -m "Initial commit: RHAII on GKE customer deployment repository

- Customer-facing deployment guides (14 files)
- Automation scripts with validation (6 files)
- Production-ready Kubernetes manifests (TPU + GPU)
- Benchmarking tools
- Cost management and troubleshooting guides"

# Add remote (replace with your repository URL)
# git remote add origin https://github.com/YOUR_ORG/rhaii-on-xks-gke.git
# git push -u origin main
```

## What's NOT Included (You Need to Provide)

1. **Secrets** (never committed to git):
   - `rhaiis-pull-secret.yaml` - Red Hat registry credentials
   - `huggingface-token-secret.yaml` - HuggingFace token

2. **External Dependencies** (clone separately):
   - RHAII on XKS repository: https://github.com/opendatahub-io/rhaii-on-xks

## Next Steps

1. Review documentation in `docs/customer-guides/`
2. Test automation scripts with `--help` flag
3. Follow a quickstart guide to validate deployment
4. Customize manifests for your use case
5. Share repository with customers

## Support

- **Documentation:** `docs/customer-guides/`
- **Troubleshooting:** `docs/customer-guides/troubleshooting.md`
- **FAQ:** `docs/customer-guides/faq.md`
- **Scripts Help:** `./scripts/<script-name>.sh --help`
