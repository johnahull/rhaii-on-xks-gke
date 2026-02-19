# Customer Guides - RHAII on GKE

Welcome to the customer-facing documentation for deploying Red Hat AI Inference Services (RHAII) on Google Kubernetes Engine (GKE).

## 📖 Deployment Guides

### Quick Demo (Recommended Starting Point)

**Try this first to see prefix caching in action:**

- **[Simple Caching Demo](../deployments/istio-kserve/simple-caching-demo/README.md)** - Single-replica deployment demonstrating 60-75% latency reduction with vLLM prefix caching

**Perfect for:**
- Evaluating vLLM prefix caching effectiveness
- Quick proof-of-concept (~20 minute deployment)
- Understanding KServe + Istio integration
- Testing before production deployment

### Prerequisites and Setup
- **[Prerequisites](prerequisites.md)** - Everything you need before starting
- **[Environment Setup](environment-setup.md)** - Optional: Configure environment variables to streamline commands
- **[Operator Installation](operator-installation.md)** - Install RHAII operators via [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks)

### Deployment
Deploy a 3-replica vLLM inference service with prefix caching and intelligent routing:

- **[RHAII Deployment Guide (TPU)](deployment-tpu.md)** - Deploy on TPU v6e (~25 req/s)
- **[RHAII Deployment Guide (GPU)](deployment-gpu.md)** - Deploy on GPU T4 (~18 req/s)

## 🛠️ Operations

- **[Verification & Testing](verification-testing.md)** - Validate your deployment
- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions

## 🔧 Automation Scripts

All guides reference these automation scripts in `/scripts/`:

- `create-gke-cluster.sh` - Automated cluster creation with validation
- `verify-deployment.sh` - Post-deployment health checks
- `preflight-check.sh` - Comprehensive prerequisite validation
- `check-accelerator-availability.sh` - Zone and accelerator validation
- `check-nodepool-prerequisites.sh` - Node pool compatibility validation

## 📚 Additional Resources

### Official Documentation
- [RHAII on XKS GitHub](https://github.com/opendatahub-io/rhaii-on-xks) - Operator installation
- [llm-d Documentation](https://llm-d.ai/docs/) - LLM framework architecture
- [GKE AI Labs](https://gke-ai-labs.dev) - Google Cloud AI on GKE resources

### Repository Documentation
- [Main README](../README.md) - Repository overview

## 🆘 Getting Help

1. **Review [Troubleshooting](troubleshooting.md)** - Solutions to common issues
3. **Check operator logs:** `kubectl logs -n <namespace> <pod-name>`
4. **Verify deployment:** `./scripts/verify-deployment.sh --operators-only`

## 📝 Feedback

Found an issue or have suggestions? Please:
- Review our [GitHub Issues](https://github.com/opendatahub-io/rhaii-on-xks/issues)
- Check deployment status with verification scripts
- Consult the troubleshooting guide for known issues

---

**Ready to get started?** Jump to:
- [Deploy on TPU](deployment-tpu.md) for maximum performance
- [Deploy on GPU](deployment-gpu.md) for wider zone availability
