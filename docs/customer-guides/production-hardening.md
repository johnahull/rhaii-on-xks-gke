# Production Hardening

Security and reliability best practices for production RHAII deployments.

## Security Hardening

### 1. Enable mTLS STRICT Mode

**Purpose:** Encrypt all pod-to-pod communication

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
```

Apply:
```bash
kubectl apply -f mtls-strict.yaml
```

### 2. Apply NetworkPolicies

**Purpose:** Restrict network traffic to required paths only

```bash
# Apply all NetworkPolicies
kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/networkpolicies/
```

**Policies:**
- Allow Istio sidecar injection
- Allow KServe controller access
- Deny all other traffic by default

### 3. RBAC Configuration

**Purpose:** Limit access to Kubernetes resources

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: inference-service-role
rules:
- apiGroups: ["serving.kserve.io"]
  resources: ["llminferenceservices"]
  verbs: ["get", "list"]
```

### 4. Secret Management

**Best practices:**
- Use Kubernetes secrets (not plain text)
- Rotate secrets regularly
- Use least-privilege access
- Consider Google Secret Manager integration

## Reliability Improvements

### 1. Resource Limits and Requests

```yaml
spec:
  resources:
    limits:
      cpu: "16"
      memory: "64Gi"
    requests:
      cpu: "8"
      memory: "32Gi"
```

**Benefits:**
- Prevents resource exhaustion
- Enables proper scheduling
- Improves cluster stability

### 2. PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: vllm-pdb
spec:
  minAvailable: 2  # For 3-replica deployment
  selector:
    matchLabels:
      serving.kserve.io/inferenceservice: gemma-2b-tpu-svc
```

**Purpose:** Maintain availability during cluster maintenance

### 3. Liveness and Readiness Probes

```yaml
spec:
  containers:
  - name: vllm
    livenessProbe:
      httpGet:
        path: /v1/health
        port: 8000
      initialDelaySeconds: 120
      periodSeconds: 30
    readinessProbe:
      httpGet:
        path: /v1/health
        port: 8000
      initialDelaySeconds: 60
      periodSeconds: 10
```

### 4. HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vllm-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vllm-deployment
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Monitoring and Observability

### 1. Metrics Collection

**Prometheus integration:**
```bash
# KServe metrics endpoint
curl http://POD_IP:8080/metrics
```

**Key metrics:**
- Request rate
- Latency (P50, P95, P99)
- Error rate
- Resource utilization

### 2. Logging

**Centralized logging:**
```bash
# Stream logs
kubectl logs -l serving.kserve.io/inferenceservice -f

# Export to Cloud Logging
# (Enabled by default on GKE)
```

### 3. Alerting

**Set up alerts for:**
- Pod crashes
- High error rate
- High latency
- Resource exhaustion
- Certificate expiration

## Backup and Recovery

### 1. Backup Configurations

```bash
# Export all manifests
kubectl get llminferenceservice -o yaml > backup-llmisvc.yaml
kubectl get httproute -o yaml > backup-httproute.yaml
kubectl get networkpolicy -o yaml > backup-netpol.yaml
```

### 2. Disaster Recovery Plan

**RTO (Recovery Time Objective):** ~30 minutes
**RPO (Recovery Point Objective):** Latest manifest commit

**Recovery procedure:**
1. Create new cluster
2. Install operators
3. Apply backed-up manifests
4. Verify deployment

## Compliance and Auditing

### 1. Audit Logging

**Enable GKE audit logs:**
```bash
# Already enabled by default on GKE
# View in Cloud Console > Logging
```

### 2. Regular Security Scans

```bash
# Scan images for vulnerabilities
gcloud container images scan IMAGEREG/IMAGE:TAG

# Review scan results
gcloud container images describe IMAGEREG/IMAGE:TAG --show-package-vulnerability
```

## Production Readiness Checklist

**Security:**
- [ ] mTLS STRICT mode enabled
- [ ] NetworkPolicies applied
- [ ] RBAC configured
- [ ] Secrets encrypted at rest
- [ ] Image scanning enabled
- [ ] Firewall rules configured

**Reliability:**
- [ ] Resource limits set
- [ ] PodDisruptionBudget configured
- [ ] Liveness/readiness probes configured
- [ ] HPA configured (if needed)
- [ ] Multi-replica deployment (for HA)

**Observability:**
- [ ] Prometheus metrics exposed
- [ ] Centralized logging configured
- [ ] Alerts configured
- [ ] Dashboards created
- [ ] On-call procedures documented

**Operations:**
- [ ] Backup procedures documented
- [ ] Disaster recovery plan tested
- [ ] Incident response plan documented
- [ ] Change management process defined
- [ ] Maintenance windows scheduled

## Testing Production Configuration

**Validate before going live:**

1. Run failure scenarios
2. Test scaling (up and down)
3. Verify backup/restore
4. Simulate incident response
5. Load test at expected traffic

## Next Steps

- [Troubleshooting](troubleshooting.md) - Common issues
- [Verification Testing](verification-testing.md) - Validation procedures
