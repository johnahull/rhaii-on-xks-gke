# RHAII on GKE — Cluster Creation

Create GKE clusters with TPU v6e or GPU T4 accelerators for **Red Hat AI Inference Services (RHAII)** vLLM workloads.

> **After cluster creation:** Install operators via [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks), then deploy RHAII workloads.

---

## Quick Start

```bash
# Create TPU cluster (europe-west4-a recommended)
make cluster-tpu ZONE=europe-west4-a

# Create GPU cluster with NVIDIA Operator
make cluster-gpu ZONE=europe-west4-a

# See all options
make help
```

**Or use scripts directly:**

```bash
./scripts/create-gke-cluster.sh --tpu --zone europe-west4-a
./scripts/create-gke-cluster.sh --gpu --zone europe-west4-a
```

---

## What This Repo Does

1. **Validates prerequisites** — tools, authentication, quota, zone availability
2. **Creates GKE control plane** — with Workload Identity, logging, monitoring
3. **Adds accelerator node pool** — TPU v6e (`ct6e-standard-4t`) or GPU T4 (`n1-standard-4`)
4. **Installs GPU Operator** (GPU path only) — NVIDIA GPU Operator v25.10+ with GKE-specific CDI configuration

What it does **not** do: operator installation, workload deployment, verification.

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make cluster-tpu` | Full TPU cluster: control plane + TPU node pool |
| `make cluster-gpu` | Full GPU cluster: control plane + GPU node pool + GPU Operator |
| `make cluster-create` | Create GKE control plane only |
| `make cluster-nodepool-tpu` | Add TPU node pool to existing cluster |
| `make cluster-nodepool-gpu` | Add GPU node pool to existing cluster |
| `make cluster-credentials` | Configure kubectl for the cluster |
| `make cluster-scale-down` | Scale accelerator pool to 0 (cost savings) |
| `make cluster-scale-up` | Scale accelerator pool back up |
| `make cluster-clean` | Delete cluster |
| `make check` | Run preflight validation only |

**Key variables:**

```bash
make cluster-tpu ZONE=europe-west4-a NUM_NODES=3 CLUSTER_NAME=my-cluster
make cluster-gpu PROJECT_ID=my-gcp-project
```

---

## Prerequisites

See [docs/prerequisites.md](docs/prerequisites.md) for full requirements. Summary:

- `gcloud` CLI installed and authenticated
- `kubectl` and `helm` installed
- GCP project with TPU v6e or GPU T4 quota

Optional: configure environment variables — see [docs/environment-setup.md](docs/environment-setup.md).

---

## Scripts

All scripts in `scripts/` support `--help`:

| Script | Purpose |
|--------|---------|
| `create-gke-cluster.sh` | Automated cluster creation with validation |
| `delete-gke-cluster.sh` | Safe cluster deletion or scale-to-zero |
| `preflight-check.sh` | Prerequisite validation |
| `check-accelerator-availability.sh` | Zone support check; `--probe` for real-time capacity |
| `check-nodepool-prerequisites.sh` | Node pool compatibility check |
| `probe-capacity.py` | Real-time parallel capacity probe across all supported zones |

---

## Recommended Zones

- **TPU v6e:** `europe-west4-a` (primary), `us-south1-a`, `us-east5-a`, `us-central1-b`
- **GPU T4:** `europe-west4-a`, `us-central1-a`, wide availability across europe-*/us-* zones

To find all available zones for your accelerator type:

```bash
# Check which zones support your accelerator type:
./scripts/check-accelerator-availability.sh --tpu
./scripts/check-accelerator-availability.sh --gpu

# Probe real-time capacity (discovers zones dynamically):
./scripts/check-accelerator-availability.sh --probe --tpu
./scripts/check-accelerator-availability.sh --probe --gpu --accelerator a100
```

---

## After Cluster Creation

Once `make cluster-tpu` or `make cluster-gpu` completes:

1. Install operators (cert-manager, Istio, KServe, LWS) from [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks)
2. Deploy RHAII workloads

---

## Cost Management

| Action | Command |
|--------|---------|
| Scale down (no cost) | `make cluster-scale-down ACCELERATOR=tpu` |
| Scale back up | `make cluster-scale-up ACCELERATOR=tpu NUM_NODES=3` |
| Delete cluster | `make cluster-clean` |

TPU v6e-1 costs ~$1.28/hour per node. Scale to zero when not in use.
