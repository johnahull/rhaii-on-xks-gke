# Environment Setup Guide

This guide explains how to configure environment variables to streamline your RHAII deployment workflow on GKE.

## Overview

RHAII automation scripts support environment variables that allow you to set common configuration values once instead of repeating them with every command. This is optional but highly recommended for improved workflow efficiency.

**Without environment variables:**
```bash
./scripts/create-gke-cluster.sh --tpu --project ecoeng-llmd --zone us-central1-b --cluster-name rhaii-cluster
./scripts/verify-deployment.sh --deployment single-model --project ecoeng-llmd --zone us-central1-b
```

**With environment variables:**
```bash
# Set once
export PROJECT_ID="ecoeng-llmd"
export ZONE="us-central1-b"
export CLUSTER_NAME="rhaii-cluster"
export ACCELERATOR_TYPE="tpu"

# Use multiple times
./scripts/create-gke-cluster.sh --tpu
./scripts/verify-deployment.sh --deployment single-model
```

## Quick Start

Choose one of two approaches:

### Option A: direnv (Recommended - Automatic)

direnv automatically loads environment variables when you enter the repository directory and unloads them when you leave.

**1. Install direnv:**
```bash
# macOS
brew install direnv

# Debian/Ubuntu
sudo apt-get install direnv

# Fedora/RHEL
sudo dnf install direnv
```

**2. Configure your shell:**

Add to `~/.bashrc` or `~/.zshrc`:
```bash
eval "$(direnv hook bash)"  # For bash
eval "$(direnv hook zsh)"   # For zsh
```

Then reload your shell:
```bash
source ~/.bashrc  # or ~/.zshrc
```

**3. Set up the repository:**
```bash
cd /path/to/rhaii-on-xks-gke
cp .envrc.example .envrc
```

**4. Edit `.envrc` with your values:**
```bash
# Replace placeholders with your actual configuration
export PROJECT_ID="your-gcp-project-id"
export ZONE="us-central1-b"
export CLUSTER_NAME="rhaii-cluster"
export ACCELERATOR_TYPE="tpu"
```

**5. Allow direnv to load the file:**
```bash
direnv allow .
```

**6. Verify:**
```bash
echo $PROJECT_ID  # Should show your project ID
cd ..
echo $PROJECT_ID  # Should be empty (auto-unloaded)
cd rhaii-on-xks-gke
echo $PROJECT_ID  # Should show your project ID again (auto-loaded)
```

### Option B: Manual Sourcing (Fallback)

If you don't want to install direnv, you can manually source an environment file.

**1. Set up the repository:**
```bash
cd /path/to/rhaii-on-xks-gke
cp env.sh.example env.sh
```

**2. Edit `env.sh` with your values:**
```bash
# Replace placeholders with your actual configuration
export PROJECT_ID="your-gcp-project-id"
export ZONE="us-central1-b"
export CLUSTER_NAME="rhaii-cluster"
export ACCELERATOR_TYPE="tpu"
```

**3. Load variables (required each session):**
```bash
source env.sh
```

**4. Verify:**
```bash
echo $PROJECT_ID  # Should show your project ID
```

**Note:** You need to run `source env.sh` in each new shell session.

## Variable Reference

### PROJECT_ID

**Description:** Your Google Cloud project ID where RHAII will be deployed.

**Required:** Yes (all scripts)

**Default fallback:** `gcloud config get-value project`

**Example:**
```bash
export PROJECT_ID="ecoeng-llmd"
```

**Override:**
```bash
./scripts/create-gke-cluster.sh --project different-project
```

### ZONE

**Description:** GCP zone for cluster and resource deployment.

**Required:** Yes (most scripts)

**Default fallback:** Script-specific (usually `us-central1-a` for GPU, varies by script)

**Recommended values:**
- **TPU v6e:** `europe-west4-a` (primary - most reliable), `us-south1-a`, `us-east5-a`, `us-central1-b`
- **GPU T4:** `europe-west4-a` (primary), `us-central1-a`, or any `europe-*`/`us-*` zone

**Check availability:**
```bash
./scripts/check-accelerator-availability.sh --zone us-central1-b --type tpu
```

**Example:**
```bash
export ZONE="us-central1-b"
```

**Override:**
```bash
./scripts/create-gke-cluster.sh --zone us-east5-a
```

### CLUSTER_NAME

**Description:** Default name for your GKE cluster.

**Required:** No

**Default fallback:** `rhaii-cluster`

**Example:**
```bash
export CLUSTER_NAME="my-production-cluster"
```

**Override:**
```bash
./scripts/verify-deployment.sh --cluster-name different-cluster
```

### ACCELERATOR_TYPE

**Description:** Default accelerator type for deployments.

**Required:** No

**Valid values:** `tpu` or `gpu`

**Default fallback:** `gpu`

**Example:**
```bash
export ACCELERATOR_TYPE="tpu"
```

**Override:**
```bash
# Override with explicit flag
./scripts/create-gke-cluster.sh --gpu  # Uses GPU even if ACCELERATOR_TYPE=tpu
```

## Variable Precedence

Scripts use the following precedence (highest to lowest):

1. **Command-line flags** (highest priority)
   ```bash
   ./scripts/create-gke-cluster.sh --zone us-east5-a
   # Uses us-east5-a even if ZONE=us-central1-b
   ```

2. **Environment variables**
   ```bash
   export ZONE="us-central1-b"
   ./scripts/create-gke-cluster.sh
   # Uses us-central1-b from environment
   ```

3. **gcloud config** (PROJECT_ID only)
   ```bash
   gcloud config set project ecoeng-llmd
   ./scripts/create-gke-cluster.sh
   # Uses ecoeng-llmd from gcloud config
   ```

4. **Script defaults** (lowest priority)
   ```bash
   ./scripts/create-gke-cluster.sh
   # Uses script's default values
   ```

## Common Workflows

### Development Workflow

Set up environment for frequent testing:

```bash
# One-time setup
cp .envrc.example .envrc
# Edit .envrc with development project and zone
direnv allow .

# Daily work - no repeated flags
./scripts/create-gke-cluster.sh --tpu
./scripts/verify-deployment.sh --deployment single-model
./scripts/cost-estimator.sh --deployment single-model

# Override for specific tests
./scripts/check-accelerator-availability.sh --zone us-east5-a
```

### Multi-Environment Workflow

Manage different environments (dev, staging, prod):

**Development:**
```bash
cd rhaii-on-xks-gke
# .envrc contains PROJECT_ID=dev-project, ZONE=us-central1-b
./scripts/create-gke-cluster.sh --tpu
```

**Production (override project):**
```bash
./scripts/create-gke-cluster.sh --tpu --project prod-project --cluster-name rhaii-prod
```

### CI/CD Pipeline

In CI/CD environments, set environment variables without using files:

```bash
export PROJECT_ID="$CI_GCP_PROJECT"
export ZONE="us-central1-b"
export CLUSTER_NAME="rhaii-${CI_ENVIRONMENT}"
./scripts/create-gke-cluster.sh --tpu
```

## Troubleshooting

### direnv Not Loading

**Symptom:** Variables are empty even after `direnv allow .`

**Solutions:**

1. Verify direnv is installed:
   ```bash
   direnv --version
   ```

2. Verify shell hook is configured:
   ```bash
   # Should show direnv hook output
   echo $BASH_ENV  # For bash
   # or check your shell config
   cat ~/.bashrc | grep direnv
   ```

3. Reload shell configuration:
   ```bash
   source ~/.bashrc
   ```

4. Re-allow the directory:
   ```bash
   direnv allow .
   ```

### Variables Not Detected by Scripts

**Symptom:** Script uses default values instead of environment variables.

**Solutions:**

1. Verify variables are exported:
   ```bash
   export PROJECT_ID="your-project"  # Correct
   PROJECT_ID="your-project"          # Wrong - not exported
   ```

2. Check variable spelling (case-sensitive):
   ```bash
   export PROJECT_ID="..."  # Correct
   export project_id="..."  # Wrong - lowercase
   ```

3. Verify you're in the correct directory:
   ```bash
   pwd  # Should be /path/to/rhaii-on-xks-gke
   echo $PROJECT_ID
   ```

### Permission Denied Error

**Symptom:** `direnv: error .envrc is blocked. Run 'direnv allow' to approve its content.`

**Solution:**
```bash
direnv allow .
```

### Variables Persist After Leaving Directory

**Symptom:** (direnv only) Variables still set after `cd ..`

**Solutions:**

1. Verify direnv hook is configured correctly:
   ```bash
   cat ~/.bashrc | grep direnv
   ```

2. Manually unset if needed:
   ```bash
   unset PROJECT_ID ZONE CLUSTER_NAME ACCELERATOR_TYPE
   ```

### gcloud Config Conflict

**Symptom:** Scripts use gcloud config project instead of environment variable.

**Explanation:** This is expected behavior. If `PROJECT_ID` is not set (either via flag or environment), scripts fall back to `gcloud config get-value project`. This is a feature, not a bug.

**Solution:** Explicitly set `PROJECT_ID` to override gcloud config:
```bash
export PROJECT_ID="specific-project"
```

## Security Considerations

### File Permissions

Both `.envrc` and `env.sh` are git-ignored to prevent accidental credential commits. Verify they're not tracked:

```bash
git status  # Should not show .envrc or env.sh
```

If accidentally committed:
```bash
git rm --cached .envrc env.sh
git commit -m "Remove environment files from tracking"
```

### Credential Management

**Do not commit credentials:**
- `.envrc` and `env.sh` are git-ignored by default
- Template files (`.envrc.example`, `env.sh.example`) contain placeholders only

**Project ID is not a secret:**
- GCP project IDs are identifiers, not credentials
- Safe to include in environment variables
- Authentication still requires `gcloud auth login`

**Token management:**
- HuggingFace tokens are managed via Kubernetes secrets (not environment variables)
- See [Quickstart Guide](quickstart-tpu.md) for secret creation

## Next Steps

After setting up your environment:

1. **Validate configuration:**
   ```bash
   ./scripts/preflight-check.sh --customer --deployment istio-kserve/baseline-pattern --accelerator tpu
   ```

2. **Create cluster:**
   - [TPU Quickstart](quickstart-tpu.md)
   - [GPU Quickstart](quickstart-gpu.md)

3. **Deploy RHAII:**
   - [Single-Model Deployment](single-model-deployment-tpu.md)
   - [Scale-Out Deployment](scale-out-deployment-tpu.md)

## Related Documentation

- [TPU Quickstart Guide](quickstart-tpu.md)
- [GPU Quickstart Guide](quickstart-gpu.md)
- [Troubleshooting Guide](troubleshooting.md)
- [FAQ](faq.md)
