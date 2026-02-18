# Troubleshooting Guide

Common issues and solutions for RHAII on GKE deployments.

## Quick Diagnostics

**Run these first:**
```bash
# Check operator status
./scripts/verify-deployment.sh --operators-only

# Check deployment status
./scripts/verify-deployment.sh

# View all pods
kubectl get pods --all-namespaces

# Check recent events
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

---

## Cluster Creation Issues

### Quota Exceeded Error

**Symptom:**
```
ERROR: (gcloud.container.clusters.create) Quota exceeded for quota metric 'GPUs_all_regions'
```

**Solution:**
1. Request quota increase: https://console.cloud.google.com/iam-admin/quotas
2. Search for specific quota (e.g., "TPU v6e" or "nvidia-tesla-t4")
3. Select region and request increase
4. Justification: "LLM inference deployment"
5. Wait for approval (24-48 hours for TPU, instant-48h for GPU)

---

### Accelerator Not Available in Zone

**Symptom:**
```
ERROR: Zone does not support TPU v6e
```

**Solution:**
```bash
# Check which zones have the accelerator
./scripts/check-accelerator-availability.sh --type tpu --customer

# Try recommended alternative zones
./scripts/create-gke-cluster.sh --tpu --zone us-south1-a
```

---

## Operator Issues

### Operator Pods Not Starting

**Symptom:**
```
pod/cert-manager-... CrashLoopBackOff
```

**Diagnosis:**
```bash
kubectl logs -n cert-manager <pod-name>
kubectl describe pod -n cert-manager <pod-name>
```

**Common causes:**
1. **Image pull errors:** Check pull secret applied
2. **Resource limits:** Check node resources
3. **Webhook conflicts:** Previous installation not cleaned up

**Solutions:**
```bash
# Verify pull secret
kubectl get secret -n cert-manager rhaiis-pull-secret

# Check node resources
kubectl top nodes

# Clean up and reinstall
# Repository: https://github.com/opendatahub-io/rhaii-on-xks
cd ~/workspace/rhaii-on-xks
make uninstall-all
make deploy-all
```

---

### Gateway No External IP

**Symptom:**
```
inference-gateway   Programmed=False
```

**Solution:**
1. Wait 2-3 minutes for GCP load balancer provisioning
2. Check gateway status:
   ```bash
   kubectl describe gateway inference-gateway -n opendatahub
   ```
3. Verify GCP quotas for load balancers
4. Check firewall rules allow port 80/443

---

## Deployment Issues

### LLMInferenceService Not READY

**Symptom:**
```
NAME              READY   URL
qwen-3b-tpu-svc  False
```

**Diagnosis:**
```bash
# Check LLMInferenceService status
kubectl describe llminferenceservice qwen-3b-tpu-svc -n rhaii-inference

# Check pods
kubectl get pods -l serving.kserve.io/inferenceservice -n rhaii-inference

# View logs
kubectl logs -l serving.kserve.io/inferenceservice -n rhaii-inference -f
```

**Common causes:**

1. **Image pull errors:**
   ```bash
   # Verify pull secret in correct namespace
   kubectl get secret rhaiis-pull-secret -n rhaii-inference

   # Reapply if missing (create from template if needed)
   # cp templates/redhat-pull.yaml.template redhat-pull-secret.yaml
   kubectl apply -n rhaii-inference -f redhat-pull-secret.yaml
   ```

2. **Model download failures:**
   ```bash
   # Check HuggingFace token
   kubectl get secret huggingface-token -n rhaii-inference

   # Verify network connectivity
   kubectl run test --image=curlimages/curl --rm -it -- curl https://huggingface.co
   ```

3. **Resource constraints:**
   ```bash
   # Check if accelerator nodes exist
   kubectl get nodes -o wide

   # Check GPU/TPU allocation
   kubectl describe nodes | grep -E "nvidia.com/gpu|cloud-tpus.google.com/chip"
   ```

---

### Pods Pending (No Accelerator Nodes)

**Symptom:**
```
pod/vllm-... 0/1 Pending
Events: 0/3 nodes available: insufficient cloud-tpus.google.com/chip
```

**Solution:**
```bash
# Check if accelerator node pool exists
kubectl get nodes

# Scale node pool if at zero
gcloud container clusters resize CLUSTER_NAME \
  --node-pool tpu-pool \
  --num-nodes 1 \
  --zone ZONE

# Verify nodes become ready
kubectl get nodes -w
```

---

## Inference Issues

### Health Endpoint Fails

**Symptom:**
```
curl http://$GATEWAY_IP/v1/health
curl: (7) Failed to connect
```

**Diagnosis:**
```bash
# Verify Gateway IP
kubectl get gateway inference-gateway -n opendatahub

# Check HTTPRoute
kubectl get httproute -n rhaii-inference

# Test from within cluster
kubectl run test --image=curlimages/curl --rm -it -- \
  curl http://inference-gateway-istio.opendatahub/v1/health
```

**Solutions:**
1. Wait for Gateway IP assignment
2. Verify HTTPRoute configured correctly
3. Check NetworkPolicy isn't blocking traffic
4. Verify firewall rules allow traffic

---

### Inference Requests Return Errors

**Symptom:**
```
{"error": "Model not loaded"}
```

**Diagnosis:**
```bash
# Check vLLM logs
kubectl logs -l serving.kserve.io/inferenceservice -n rhaii-inference -f

# Look for model loading messages
# Expected: "Loaded model Qwen/Qwen2.5-3B-Instruct"
```

**Common causes:**
1. Model still downloading (wait 2-5 minutes)
2. HuggingFace token invalid or model access denied
3. Insufficient GPU/TPU memory for model

---

### Slow First Inference (TPU)

**Symptom:**
First inference takes 10-30 seconds

**Explanation:**
This is expected! TPU uses XLA compilation:
- First inference: ~10-30s (compiles computational graph)
- Subsequent inferences: <200ms

**Not a problem:** This is normal TPU behavior.

---

## Performance Issues

### Low Throughput

**Symptom:**
Performance lower than expected

**Diagnosis:**
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -l serving.kserve.io/inferenceservice

# Check for CPU/memory throttling
kubectl describe pod <vllm-pod-name> | grep -A 10 "Limits\|Requests"
```

**Solutions:**
1. Verify accelerator is being used (check logs for GPU/TPU detection)
2. Check batch size configuration
3. For scale-out: Verify all replicas running
4. Monitor GPU utilization: `kubectl exec -it <pod> -- nvidia-smi` (GPU only)

---

### High Latency

**Diagnosis:**
```bash
# Test latency
time curl -X POST http://$GATEWAY_IP/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-3B-Instruct", "prompt": "Test", "max_tokens": 10}'
```

**Common causes:**
1. Cold start (first request after pod creation)
2. Large input/output tokens
3. Network latency to Gateway
4. Multiple concurrent requests saturating accelerator

---

## Scale-Out Specific Issues

### Cache Routing Not Working

**Symptom:**
Requests with same prefix go to different replicas

**Verification:**
```bash
# Test cache-aware routing
for i in {1..10}; do
  curl -s http://$GATEWAY_IP/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "Qwen/Qwen2.5-3B-Instruct", "prompt": "Shared prefix test", "max_tokens": 5}' | \
  grep -o "pod-name.*"
done

# All requests should hit same pod
```

**Solution:**
Verify EnvoyFilter for extproc body forwarding is applied

---

### NetworkPolicy Blocking Traffic

**Symptom:**
```
Error: connection refused from pod to pod
```

**Diagnosis:**
```bash
# List NetworkPolicies
kubectl get networkpolicy -n rhaii-inference

# Test connectivity
kubectl run test --image=curlimages/curl --rm -it -- \
  curl http://POD_IP:8000/v1/health
```

**Solution:**
Review and update NetworkPolicy to allow required traffic.

---

## Resource Management

### Unused Resources Still Running

**Check running resources:**
```bash
# List all clusters
gcloud container clusters list --project=YOUR_PROJECT

# Check node pools
gcloud container node-pools list --cluster=CLUSTER_NAME --zone=ZONE

# Verify accelerator nodes
kubectl get nodes -o wide
```

**Solution:**
Scale down when not in use:
```bash
# Scale accelerator node pool to zero
gcloud container clusters resize CLUSTER_NAME \
  --node-pool tpu-pool \
  --num-nodes 0 \
  --zone ZONE
```

See the deployment guides for scale-to-zero procedures.

---

## Script and Automation Issues

### Environment Variables Not Detected

**Symptom:** Scripts use default values instead of environment variables.

**Causes:**
1. Variables not exported
2. Incorrect variable names (case-sensitive)
3. Not in correct directory (direnv only)

**Solutions:**

**1. Verify variables are exported:**
```bash
# Correct
export PROJECT_ID="your-project"

# Wrong - not exported
PROJECT_ID="your-project"
```

**2. Check variable names:**
```bash
# Correct
export PROJECT_ID="..."
export ZONE="..."
export CLUSTER_NAME="..."
export ACCELERATOR_TYPE="..."

# Wrong - case matters
export project_id="..."
```

**3. Verify direnv is working:**
```bash
# Check direnv is installed
direnv version

# Check hook is configured
cat ~/.bashrc | grep direnv

# Re-allow directory
direnv allow .

# Verify variables loaded
echo $PROJECT_ID
```

**4. For manual sourcing:**
```bash
# Source the file
source env.sh

# Verify
echo $PROJECT_ID
```

---

### CLI Flags Not Overriding Environment Variables

**This should not happen** - CLI flags always override environment variables.

**If experiencing this issue:**

1. Verify you're using the latest scripts:
   ```bash
   git pull origin main
   ```

2. Check script version includes environment variable support:
   ```bash
   grep "Load from environment" scripts/preflight-check.sh
   ```

Expected output: Should show comment about environment variable loading.

---

### direnv Not Loading Automatically

**Symptom:** Variables empty when entering directory.

**Solutions:**

1. **Verify direnv hook is configured:**
   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   eval "$(direnv hook bash)"  # For bash
   eval "$(direnv hook zsh)"   # For zsh

   # Reload shell
   source ~/.bashrc
   ```

2. **Allow the directory:**
   ```bash
   cd /path/to/rhaii-on-xks-gke
   direnv allow .
   ```

3. **Check for errors:**
   ```bash
   direnv status
   ```

See [Environment Setup Guide](environment-setup.md) for complete troubleshooting.

---

## Getting More Help

**Collect diagnostics:**
```bash
# Operator logs
kubectl logs -n cert-manager deployment/cert-manager
kubectl logs -n istio-system deployment/istiod
kubectl logs -n opendatahub deployment/kserve-controller-manager

# Application logs
kubectl logs -l serving.kserve.io/inferenceservice -n rhaii-inference --tail=100

# Events
kubectl get events --sort-by='.lastTimestamp' | tail -50

# Resource status
kubectl describe llminferenceservice <name> -n rhaii-inference
kubectl describe pod <pod-name> -n rhaii-inference
```

**Check documentation:**
- [RHAII on XKS Issues](https://github.com/opendatahub-io/rhaii-on-xks/issues)
- [RHAII on XKS Issues](https://github.com/opendatahub-io/rhaii-on-xks/issues)
- [KServe Documentation](https://kserve.github.io/website/)
- [Istio Documentation](https://istio.io/latest/docs/)

---

**Still stuck?** Review logs carefully and search for specific error messages in GitHub issues.
