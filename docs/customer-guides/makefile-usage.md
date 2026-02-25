# Makefile Usage Guide

This guide explains how to use the Makefile for GKE cluster lifecycle management.

## Prerequisites

- gcloud CLI installed and authenticated
- kubectl installed
- helm installed (for GPU clusters)
- Red Hat registry credentials configured
- HuggingFace token available

## Configuration

All configuration is done via Make variables. You can:

1. **Edit the Makefile** - Change default values at the top
2. **Override via command line** - `make cluster-tpu ZONE=us-east5-a`
3. **Set environment variables** - `export PROJECT_ID=my-project`

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_ID` | gcloud config | GCP project ID |
| `CLUSTER_NAME` | rhaii-cluster | Cluster name |
| `ZONE` | europe-west4-a | GCP zone |
| `ACCELERATOR` | tpu | Accelerator type (tpu or gpu) |
| `NUM_NODES` | 3 | Number of accelerator nodes |

## Common Workflows

### Create TPU Cluster

```bash
make cluster-tpu
```

This runs: check → cluster-create → cluster-nodepool-tpu → cluster-credentials

### Create GPU Cluster

```bash
make cluster-gpu
```

This runs: check → cluster-create → cluster-nodepool-gpu → cluster-credentials → deploy-gpu-operator

### Scale for Cost Savings

```bash
# Scale down to 0 nodes
make cluster-scale-down ACCELERATOR=tpu

# Scale back up to 3 nodes
make cluster-scale-up ACCELERATOR=tpu NUM_NODES=3
```

### Delete Cluster

```bash
make cluster-clean
```

Deletes cluster and cleans up local kubeconfig and Helm repos.

## Advanced Usage

### Individual Targets

Run targets independently:

```bash
# Just validate prerequisites
make check

# Create control plane only
make cluster-create ACCELERATOR=tpu

# Add GPU node pool to existing cluster
make cluster-nodepool-gpu

# Deploy GPU operator manually
make deploy-gpu-operator
```

### Custom Configuration

```bash
# Single-node test cluster
make cluster-tpu NUM_NODES=1 CLUSTER_NAME=test-cluster

# GPU cluster in specific project/zone
make cluster-gpu PROJECT_ID=my-project ZONE=us-central1-a
```

## Troubleshooting

### "gcloud not found"

Install gcloud: https://cloud.google.com/sdk/docs/install

### "Not authenticated with gcloud"

Run: `gcloud auth login`

### "Cluster already exists"

Delete first: `make cluster-clean`

Or use a different name: `make cluster-tpu CLUSTER_NAME=new-name`

## Comparison with Bash Scripts

The Makefile wraps the existing bash scripts in `scripts/`:

| Makefile Target | Equivalent Script |
|-----------------|-------------------|
| `make cluster-tpu` | `./scripts/create-gke-cluster.sh --tpu` |
| `make check` | `./scripts/preflight-check.sh` |
| `make cluster-clean` | `./scripts/delete-gke-cluster.sh` |

**Use Makefile for:**
- Automation and CI/CD
- Consistent interface with AKS deployment
- Composed workflows

**Use bash scripts for:**
- Interactive prompts and guidance
- Detailed error messages
- Step-by-step execution
