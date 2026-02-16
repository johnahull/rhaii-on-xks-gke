# Customer Guides - RHAII on GKE

Welcome to the customer-facing documentation for deploying Red Hat AI Inference Services (RHAII) on Google Kubernetes Engine (GKE).

## 🚀 Quick Start

**New to RHAII on GKE?** Start here:

- **[30-Minute TPU Quickstart](quickstart-tpu.md)** - Deploy RHAII on TPU v6e (~$132/day)
- **[30-Minute GPU Quickstart](quickstart-gpu.md)** - Deploy RHAII on GPU T4 (~$80/day)

## 📖 Deployment Guides

### Prerequisites and Setup
- **[Prerequisites](prerequisites.md)** - Everything you need before starting
- **[Environment Setup](environment-setup.md)** - Optional: Configure environment variables to streamline commands
- **[Operator Installation](operator-installation.md)** - Install RHAII operators via [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks)

### Single-Model Deployments (Baseline)
Best for development, testing, and traffic <10 req/s:

- **[Single-Model Deployment (TPU)](single-model-deployment-tpu.md)** - Deploy on TPU v6e
- **[Single-Model Deployment (GPU)](single-model-deployment-gpu.md)** - Deploy on GPU T4

### High-Throughput Scale-Out Deployments
Best for production workloads with >10 req/s and shared prompts:

- **[Scale-Out Deployment (TPU)](scale-out-deployment-tpu.md)** - 3-replica deployment with prefix caching (TPU)
- **[Scale-Out Deployment (GPU)](scale-out-deployment-gpu.md)** - 3-replica deployment with prefix caching (GPU)

## 🛠️ Operations

- **[Verification & Testing](verification-testing.md)** - Validate your deployment
- **[Production Hardening](production-hardening.md)** - Security and reliability best practices
- **[Cost Management](cost-management.md)** - Optimize and control costs
- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions
- **[FAQ](faq.md)** - Frequently asked questions

## 🎯 Deployment Decision Guide

### When to use TPU vs GPU?

**Choose TPU if:**
- You need maximum performance (~7-8 req/s single-model, ~25 req/s scale-out)
- You have production workloads with consistent traffic
- Budget allows ~$132/day for single-model deployment

**Choose GPU if:**
- You're doing PoC or development work
- You need lower costs (~$80/day for single-model deployment)
- You need wider zone availability

### When to use Single-Model vs Scale-Out?

**Single-Model Deployment when:**
- Traffic <10 req/s
- Development or testing workloads
- Cost-sensitive deployments
- Getting started with RHAII

**Scale-Out Deployment when:**
- Traffic >10 req/s
- Production workloads with high availability requirements
- Workloads with shared prompts (benefits from prefix caching)
- Need 3.3× better throughput (worth 2.9× cost increase)

## 💰 Cost Comparison

| Deployment Type | TPU v6e Cost | GPU T4 Cost | Performance |
|----------------|--------------|-------------|-------------|
| Single-Model   | ~$132/day    | ~$80/day    | 7-8 req/s (TPU), 5-6 req/s (GPU) |
| Scale-Out (3x) | ~$377/day    | ~$228/day   | 25 req/s (TPU), 18 req/s (GPU) |
| **Scaled to 0** | ~$6/day | ~$6/day | 0 req/s (cluster overhead only) |

> **Cost Tip:** Scale node pools to 0 when not in use to minimize costs. See [Cost Management](cost-management.md).

## 🔧 Automation Scripts

All guides reference these automation scripts in `/scripts/`:

- `create-gke-cluster.sh` - Automated cluster creation with validation
- `verify-deployment.sh` - Post-deployment health checks
- `cost-estimator.sh` - Cost calculation and comparison
- `preflight-check.sh` - Comprehensive prerequisite validation
- `check-accelerator-availability.sh` - Zone and accelerator validation
- `check-nodepool-prerequisites.sh` - Node pool compatibility validation

## 📚 Additional Resources

### Official Documentation
- [RHAII on XKS GitHub](https://github.com/opendatahub-io/rhaii-on-xks) - Operator installation
- [llm-d Documentation](https://llm-d.ai/docs/) - LLM framework architecture
- [GKE AI Labs](https://gke-ai-labs.dev) - Google Cloud AI on GKE resources

### Repository Documentation
- [Technical Guides](../README.md) - Developer-focused documentation
- [Benchmarking Guide](../benchmarking.md) - Performance testing procedures
- [Main README](../../README.md) - Repository overview

## 🆘 Getting Help

1. **Check the [FAQ](faq.md)** - Common questions and answers
2. **Review [Troubleshooting](troubleshooting.md)** - Solutions to common issues
3. **Check operator logs:** `kubectl logs -n <namespace> <pod-name>`
4. **Verify deployment:** `./scripts/verify-deployment.sh --operators-only`

## 📝 Feedback

Found an issue or have suggestions? Please:
- Review our [GitHub Issues](https://github.com/opendatahub-io/rhaii-on-xks/issues)
- Check deployment status with verification scripts
- Consult the troubleshooting guide for known issues

---

**Ready to get started?** Jump to:
- [TPU Quickstart](quickstart-tpu.md) for maximum performance
- [GPU Quickstart](quickstart-gpu.md) for cost-effective PoC
