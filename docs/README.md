# RHAII on GKE - Deployment Guides

Documentation for deploying Red Hat AI Inference Services (RHAII) on Google Kubernetes Engine (GKE).

## Get Started

### Prerequisites and Setup
- **[Prerequisites](prerequisites.md)** - Everything you need before starting
- **[Environment Setup](environment-setup.md)** - Optional: Configure environment variables to streamline commands
- **[Operator Installation](operator-installation.md)** - Install RHAII operators via [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks)

### Single Replica with Prefix Caching

Single-replica deployment demonstrating vLLM prefix caching effectiveness. Lower cost, simpler configuration.

- **[Single Replica - TPU](../deployments/istio-kserve/simple-caching-demo/deployment-tpu.md)** - 1 TPU node, ~8.3 req/s, ~$15/day
- **[Single Replica - GPU](../deployments/istio-kserve/simple-caching-demo/deployment-gpu.md)** - 1 GPU node, ~6 req/s, ~$12/day
- **[Pattern Overview](../deployments/istio-kserve/simple-caching-demo/README.md)** - Architecture and technical details

## 📖 Deployment Guides

### 3-Replica Deployment with Cache-Aware Routing

3-replica deployment with cache-aware routing for higher throughput.

- **[3-Replica - TPU](deployment-tpu.md)** - 3 TPU nodes, ~25 req/s, ~$46/day
- **[3-Replica - GPU](deployment-gpu.md)** - 3 GPU nodes, ~18 req/s, ~$36/day

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
2. **Check operator logs:** `kubectl logs -n <namespace> <pod-name>`
3. **Verify deployment:** `./scripts/verify-deployment.sh --operators-only`

## 📝 Feedback

Found an issue or have suggestions? Please:
- Review our [GitHub Issues](https://github.com/opendatahub-io/rhaii-on-xks/issues)
- Check deployment status with verification scripts
- Consult the troubleshooting guide for known issues
