# Prerequisites

Everything you need before deploying RHAII on GKE.

## Required Accounts and Access

### Google Cloud Platform

- **GCP Account:** Active account with billing enabled
- **Project:** Existing GCP project with appropriate quotas
  - Recommended: Create new project for RHAII deployments
  - Required permissions: Owner or Editor role
- **Billing:** Enabled with valid payment method

### Red Hat Registry

- **Red Hat Account:** Access to registry.redhat.io
- **Pull Secret:** Registry credentials for RHAII images
  - Location: `redhat-pull-secret.yaml`
  - Format: Kubernetes secret with `.dockerconfigjson`

### HuggingFace

- **HuggingFace Account:** Free account at huggingface.co
- **Access Token:** Read token for model downloads
  - Create at: https://huggingface.co/settings/tokens
  - Permissions: Read access sufficient
  - Gated models: Accept license agreements for models you'll use

---

## Required Tools

Install these CLI tools before proceeding:

### gcloud CLI

**Purpose:** Manage GCP resources, authenticate, create clusters

**Installation:**
```bash
# Linux
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# macOS (Homebrew)
brew install google-cloud-sdk

# Verify
gcloud version
```

**Configuration:**
```bash
# Authenticate
gcloud auth login

# Set project
gcloud config set project YOUR_PROJECT_ID

# Set default zone (optional)
gcloud config set compute/zone us-central1-a
```

**Required version:** ≥ 400.0.0

### kubectl

**Purpose:** Manage Kubernetes resources

**Installation:**
```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# macOS (Homebrew)
brew install kubectl

# Verify
kubectl version --client
```

**Required version:** ≥ 1.28

### jq

**Purpose:** JSON parsing for automation scripts

**Installation:**
```bash
# Linux (Red Hat/Fedora)
sudo dnf install jq

# Linux (Debian/Ubuntu)
sudo apt-get install jq

# macOS (Homebrew)
brew install jq

# Verify
jq --version
```

**Required version:** ≥ 1.6

---

## GCP Quotas

Request quota increases before creating clusters:

### TPU Deployment Quotas

**Required:** 12 TPU v6e chips (3 nodes × 4 chips each)

**How to request:**
1. Navigate to: https://console.cloud.google.com/iam-admin/quotas
2. Search: "TPU v6e" and select region (e.g., us-central1)
3. Click "EDIT QUOTAS"
4. Request: 12 chips
5. Justification: "LLM inference deployment for production workloads"
6. Submit request

**Approval time:** Usually 24-48 hours

### GPU Deployment Quotas

**Required:** 3 T4 GPUs

**How to request:**
1. Navigate to: https://console.cloud.google.com/iam-admin/quotas
2. Search: "nvidia-tesla-t4" and select region
3. Click "EDIT QUOTAS"
4. Request: 3 GPUs
5. Justification: "LLM inference deployment for development/testing"
6. Submit request

**Approval time:**
- T4: Usually instant or within hours
- A100/H100: 24-48 hours

### Additional Quotas

**All Deployments:**
- CPUs: 50+ (for cluster nodes)
- In-use IP addresses: 10+
- Load balancers: 5+

---

## Required Secrets

### Red Hat Pull Secret

**Template:** `templates/redhat-pull.yaml.template`

**Create from template:**
```bash
cp templates/redhat-pull.yaml.template redhat-pull-secret.yaml
```

Then edit `redhat-pull-secret.yaml` and replace `BASE64_ENCODED_DOCKERCONFIGJSON` with your credentials.

**How to obtain credentials:**
1. Log in to Red Hat registry: https://registry.redhat.io
2. Navigate to: Registry Service Accounts
3. Create or use existing service account
4. Download Kubernetes secret (YAML format) and copy the `.dockerconfigjson` value

**Alternative — create directly with kubectl:**
```bash
kubectl create secret docker-registry rhaiis-pull-secret \
  --docker-server=registry.redhat.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD \
  -n rhaii-inference
```

### HuggingFace Token Secret

**Template:** `templates/huggingface-token.yaml.template`

**Create from template:**
```bash
cp templates/huggingface-token.yaml.template huggingface-token-secret.yaml
```

Then edit `huggingface-token-secret.yaml` and replace `YOUR_HF_TOKEN_HERE` with your token.

**How to obtain:**
1. Get token from: https://huggingface.co/settings/tokens
2. Accept license for gated models you'll use (default model Qwen/Qwen2.5-3B-Instruct is ungated)

**Note:** Secret files (`*secret*.yaml`) are git-ignored and will not be committed.

---

## Istio CNI Requirement

**CRITICAL:** This deployment requires Istio service mesh with CNI (Container Network Interface) plugin enabled.

### What is Istio CNI?

Istio CNI is a container network plugin that replaces Istio's default init container approach for configuring pod networking. It's required for proper sidecar injection and mTLS communication between services.

### Why is CNI Required?

**This architecture depends on Istio CNI for:**

1. **EPP Scheduler mTLS Communication**
   - EPP (External Processing Protocol) scheduler pod requires Istio sidecar injection
   - Without CNI, init container network conflicts prevent proper mTLS setup
   - ext_proc filter communication will fail without CNI

2. **Gateway to EPP Routing**
   - Istio Gateway uses ext_proc filter to communicate with EPP scheduler via gRPC
   - Communication uses Istio mTLS (mutual TLS) for security
   - CNI ensures proper network namespace setup for mTLS handshake

3. **Service Mesh Security**
   - Zero-trust architecture with mutual TLS authentication
   - SPIFFE workload identity for service-to-service auth
   - Network policies work correctly with CNI-managed networking

### Istio CNI vs Init Container

| Aspect | Init Container (Default) | CNI Plugin (Required) |
|--------|-------------------------|----------------------|
| **Network Setup** | Per-pod init container | DaemonSet on each node |
| **Permissions** | Requires NET_ADMIN capability | No elevated pod permissions needed |
| **Startup Order** | Init container runs first | Network setup before pod starts |
| **mTLS with ext_proc** | ❌ Conflicts with EPP scheduler | ✅ Works correctly |
| **Security** | Higher pod privileges | Lower pod privileges (better) |

### Installation

**Istio CNI is installed automatically via the RHAII on XKS repository.**

See [Operator Installation Guide](operator-installation.md) for complete installation instructions.

**Installation command (from rhaii-on-xks repository):**
```bash
cd /path/to/rhaii-on-xks
make deploy-all  # Installs Istio with CNI enabled
```

### Verification

**After operator installation, verify Istio CNI is running:**

```bash
# Check CNI DaemonSet exists
kubectl get daemonset -n istio-system istio-cni-node

# Verify CNI pods are running on all nodes
kubectl get pods -n istio-system -l k8s-app=istio-cni-node

# Check CNI configuration
kubectl get configmap -n istio-system istio-cni-config -o yaml
```

**Expected output:**
```
NAME              DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
istio-cni-node    3         3         3       3            3
```

**If CNI is missing:**
```bash
❌ ERROR: Istio CNI not detected

This deployment requires Istio CNI for EPP scheduler mTLS communication.

Install RHAII operators with CNI enabled:
  cd /path/to/rhaii-on-xks
  make deploy-all
```

### Troubleshooting CNI Issues

**EPP scheduler mTLS failures:**
```bash
# Check if CNI is running
kubectl get pods -n istio-system -l k8s-app=istio-cni-node

# Check sidecar injection on EPP scheduler
kubectl get pods -n rhaii-inference -l app.kubernetes.io/component=router-scheduler -o yaml | grep -A 5 "istio-proxy"

# Verify mTLS cluster connectivity
kubectl logs -n opendatahub <gateway-pod> | grep -i "epp.*mtls\|ext_proc"
```

**Common CNI issues:**
- CNI pods not running: Re-deploy Istio operators
- Sidecar not injected: Check namespace has `istio-injection=enabled` label
- mTLS handshake failures: Verify CNI network configuration

### Additional Resources

- **RHAII on XKS:** https://github.com/opendatahub-io/rhaii-on-xks
- **Istio CNI Documentation:** https://istio.io/latest/docs/setup/additional-setup/cni/
- **GKE + Istio CNI:** https://cloud.google.com/service-mesh/docs/managed/configure-cni

---

## Zone Selection

### TPU Zones

**Recommended zones for TPU v6e:**
1. `europe-west4-a` (Netherlands) ⭐ Most reliable
2. `us-south1-a` (Dallas)
3. `us-east5-a` (Columbus)
4. `europe-west4-a` (Central US)
5. `us-south1-b` (Dallas)

**Check availability:**
```bash
./scripts/check-accelerator-availability.sh --type tpu --customer
```

### GPU Zones

**Recommended zones for T4 GPUs:**
1. `europe-west4-a/b` (Netherlands) ⭐ Primary
2. `us-central1-a/b/c/f` (Central US)
3. `us-east1-b/c/d` (South Carolina)
4. `us-east4-a/b/c` (Virginia)
5. `us-west1-a/b` (Oregon)

**Check availability:**
```bash
./scripts/check-accelerator-availability.sh --type gpu --customer
```

---

## Repository Setup

### Clone Repository

```bash
# Clone rhaii-on-xks-gke repository
cd ~/workspace
git clone https://github.com/YOUR_ORG/rhaii-on-xks-gke.git
cd rhaii-on-xks-gke

# Clone RHAII on XKS repository for operator installation
# Repository: https://github.com/opendatahub-io/rhaii-on-xks
cd ~/workspace
git clone https://github.com/opendatahub-io/rhaii-on-xks.git
```

**Directory structure:**
```
~/workspace/
├── rhaii-on-xks-gke/         # This repository
└── rhaii-on-xks/          # Operator installation (https://github.com/opendatahub-io/rhaii-on-xks)
```

### Create Secrets from Templates

```bash
cd ~/workspace/rhaii-on-xks-gke

# Create secret files from templates
cp templates/redhat-pull.yaml.template redhat-pull-secret.yaml
cp templates/huggingface-token.yaml.template huggingface-token-secret.yaml

# Edit each file and replace placeholders with your credentials
# (see "Required Secrets" section above for details)

# Verify secrets exist
ls -l *secret*.yaml
```

---

## Validation

Run the comprehensive preflight check to verify all prerequisites:

```bash
cd ~/workspace/rhaii-on-xks-gke

# For TPU deployment (defaults to europe-west4-a)
./scripts/preflight-check.sh --tpu --customer

# For GPU deployment (defaults to us-central1-a)
./scripts/preflight-check.sh --gpu --customer

# Or with explicit zone:
# ./scripts/preflight-check.sh --tpu --zone us-south1-a --customer
```

**What it checks:**
- ✅ Tool installation (gcloud, kubectl, jq)
- ✅ GCP authentication
- ✅ IAM permissions
- ✅ Accelerator availability in zone
- ✅ Secret files exist and valid
- ✅ [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) repository cloned

**Success criteria:** All checks pass before proceeding to cluster creation.

---

## Estimated Setup Time

- Account setup: 1-2 hours (one-time)
- Tool installation: 15-30 minutes (one-time)
- Quota requests: 24-48 hours wait (one-time)
- Secret creation: 15 minutes (one-time)

---

## Next Steps

After completing prerequisites:

1. **Optional:** Configure [Environment Setup](environment-setup.md) to streamline commands
2. **TPU Deployment:** Follow [RHAII Deployment Guide (TPU)](deployment-tpu.md)
3. **GPU Deployment:** Follow [RHAII Deployment Guide (GPU)](deployment-gpu.md)

**Questions?** See [Troubleshooting](troubleshooting.md)
