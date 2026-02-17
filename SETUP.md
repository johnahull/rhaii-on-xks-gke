# Repository Setup Guide

This repository contains everything needed to deploy RHAII on GKE.

## What's Included

### Documentation (9 files)
```
docs/customer-guides/
├── README.md                          # Navigation index
├── deployment-tpu.md                  # TPU deployment guide
├── deployment-gpu.md                  # GPU deployment guide
├── prerequisites.md                   # Setup requirements
├── environment-setup.md               # Environment variable configuration
├── operator-installation.md           # RHAII operator installation
├── verification-testing.md            # Validation procedures
├── troubleshooting.md                 # Common issues
└── faq.md                             # FAQ
```

### Automation Scripts (6 files)
```
scripts/
├── create-gke-cluster.sh              # Cluster creation
├── delete-gke-cluster.sh              # Cluster deletion / scale-to-zero
├── verify-deployment.sh               # Post-deployment validation
├── preflight-check.sh                 # Prerequisite validation
├── check-accelerator-availability.sh  # Zone validation
└── check-nodepool-prerequisites.sh    # Node pool validation
```

### Kubernetes Manifests
```
deployments/istio-kserve/
└── caching-pattern/manifests/         # Customer deployment manifests
    ├── llmisvc-tpu-caching.yaml
    ├── llmisvc-gpu-caching.yaml
    ├── envoyfilter-route-extproc-body.yaml
    └── networkpolicies/
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

- **Documentation:** 9 customer guides
- **Scripts:** 6 automation scripts
- **Manifests:** 7 Kubernetes YAML files
- **Benchmarks:** Benchmarking tools and utilities
- **Total:** 35+ files ready for customer use

## Getting Started

### For New Users

1. **Read the documentation:**
   ```bash
   cat docs/customer-guides/README.md
   ```

2. **Choose your deployment:**
   - TPU: `docs/customer-guides/deployment-tpu.md`
   - GPU: `docs/customer-guides/deployment-gpu.md`

3. **Run validation:**
   ```bash
   ./scripts/preflight-check.sh --customer --accelerator tpu
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

- Customer-facing deployment guides (9 files)
- Automation scripts with validation (6 files)
- Production-ready Kubernetes manifests (TPU + GPU)
- Benchmarking tools"

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
3. Follow a deployment guide to validate deployment
4. Customize manifests for your use case
5. Share repository with customers

## Support

- **Documentation:** `docs/customer-guides/`
- **Troubleshooting:** `docs/customer-guides/troubleshooting.md`
- **FAQ:** `docs/customer-guides/faq.md`
- **Scripts Help:** `./scripts/<script-name>.sh --help`
