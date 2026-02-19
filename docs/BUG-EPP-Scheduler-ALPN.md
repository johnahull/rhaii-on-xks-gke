# Bug Report: EPP Scheduler gRPC Server Missing ALPN Support

**Date:** 2026-02-19
**Component:** llm-d-inference-scheduler (EPP Scheduler)
**Severity:** Critical - Blocks Envoy ext_proc integration
**Affected Image:** `ghcr.io/opendatahub-io/rhaii-on-xks/llm-d-inference-scheduler:e6b5db0`

## Summary

The EPP (External Processing Protocol) scheduler's gRPC server does NOT negotiate ALPN (Application-Layer Protocol Negotiation) for HTTP/2 when TLS is enabled (`--secure-serving`). This causes Envoy ext_proc filter connections to fail with TLS errors, preventing cache-aware routing from functioning.

## Impact

- **Envoy ext_proc integration fails completely** - ext_proc filter cannot connect to EPP scheduler over TLS
- **Cache-aware routing broken** - vLLM prefix caching shows ZERO cache hits despite correct configuration
- **KServe LLMInferenceService integration broken** - EPP scheduler cannot be used with Istio service mesh

## Root Cause

The EPP scheduler's gRPC server, when configured with `--secure-serving` and `--cert-path`, serves TLS but **does not advertise HTTP/2 (h2) support via ALPN**.

### Evidence

**Test 1: OpenSSL client with ALPN h2 request**
```bash
$ openssl s_client -connect qwen-3b-tpu-svc-epp-service.rhaii-inference.svc.cluster.local:9002 \
  -alpn h2 -CAfile /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem

...
No ALPN negotiated  ← SERVER DOES NOT SUPPORT ALPN
Verify return code: 0 (ok)
```

**Test 2: Envoy ext_proc gRPC client**
```
gRPC stream closed remotely with status 14: upstream connect error or disconnect/reset before headers.
reset reason: remote connection failure,
transport failure reason: TLS_error:|2147483752:system library:OPENSSL_internal:unknown error
```

**Test 3: Basic TLS (without ALPN)**
```bash
$ openssl s_client -connect qwen-3b-tpu-svc-epp-service.rhaii-inference.svc.cluster.local:9002

...
Verify return code: 0 (ok)  ← TLS WORKS WITHOUT ALPN
```

## Expected Behavior

The gRPC server should:
1. Advertise HTTP/2 (`h2`) support via ALPN during TLS handshake
2. Successfully negotiate ALPN with Envoy's gRPC client
3. Accept gRPC connections over TLS with HTTP/2

## Actual Behavior

The gRPC server:
1. Serves TLS but does NOT advertise ALPN protocols
2. TLS handshake succeeds for basic connections (openssl s_client)
3. gRPC connections fail because Envoy **requires** ALPN h2 negotiation

## Technical Details

**EPP Scheduler Configuration:**
```yaml
args:
  - --grpc-port=9002
  - --grpc-health-port=9003
  - --secure-serving              # Enables TLS
  - --cert-path=/var/run/kserve/tls  # TLS certificates
```

**Envoy ext_proc Configuration:**
```yaml
grpc_service:
  envoy_grpc:
    cluster_name: outbound|9002||qwen-3b-tpu-svc-epp-service...
  timeout: 10s
# Envoy REQUIRES ALPN h2 for gRPC over TLS
```

**Go gRPC Library Behavior:**
- Go's `google.golang.org/grpc` library **automatically** enables ALPN for `h2` when using TLS
- If ALPN is NOT working, the code is likely using a **custom TLS configuration** that doesn't include `NextProtos`

## Likely Code Issue

The EPP scheduler's gRPC server TLS configuration is missing `NextProtos`:

**Current (Broken):**
```go
// Somewhere in llm-d-inference-scheduler code
tlsConfig := &tls.Config{
    Certificates: []tls.Certificate{cert},
    // Missing: NextProtos: []string{"h2"},  ← THIS IS THE BUG
}
grpc.NewServer(grpc.Creds(credentials.NewTLS(tlsConfig)))
```

**Fixed:**
```go
tlsConfig := &tls.Config{
    Certificates: []tls.Certificate{cert},
    NextProtos:   []string{"h2"},  ← ADD THIS
}
grpc.NewServer(grpc.Creds(credentials.NewTLS(tlsConfig)))
```

**OR (Preferred):** Use grpc's automatic TLS config:
```go
creds, err := credentials.NewServerTLSFromFile(certFile, keyFile)
// grpc automatically sets NextProtos: []string{"h2"}
grpc.NewServer(grpc.Creds(creds))
```

## Workaround

**Temporary workaround:** Disable TLS on EPP scheduler (remove `--secure-serving` and `--cert-path`)

```yaml
# Deployment patch to disable TLS
args:
  - --grpc-port=9002
  - --grpc-health-port=9003
  # REMOVED: --secure-serving
  # REMOVED: --cert-path=/var/run/kserve/tls
```

**Note:** This workaround is acceptable in Istio service mesh environments where mTLS is already enforced by the mesh, but it's **NOT a proper solution** for production.

## Reproduction Steps

1. Deploy KServe LLMInferenceService with EPP scheduler
2. EPP scheduler pod starts with `--secure-serving --cert-path /var/run/kserve/tls`
3. Envoy ext_proc filter configured to connect to EPP scheduler on port 9002
4. Send HTTP request through Istio Gateway
5. Observe TLS error in Gateway logs:
   ```
   gRPC stream closed remotely with status 14: upstream connect error
   transport failure reason: TLS_error:|2147483752:system library:OPENSSL_internal:unknown error
   ```
6. Verify EPP scheduler logs show ZERO incoming requests (connection fails before reaching application)

## Diagnostic Commands

```bash
# Test ALPN negotiation
kubectl exec -n opendatahub $GATEWAY_POD -c istio-proxy -- \
  sh -c "echo '' | openssl s_client -connect qwen-3b-tpu-svc-epp-service.rhaii-inference.svc.cluster.local:9002 \
  -alpn h2 2>&1" | grep ALPN

# Enable Envoy debug logging
kubectl exec -n opendatahub $GATEWAY_POD -c istio-proxy -- \
  pilot-agent request POST "logging?ext_proc=debug"

# Check ext_proc errors
kubectl logs -n opendatahub $GATEWAY_POD -c istio-proxy | grep ext_proc
```

## References

- **gRPC over TLS requirements:** https://grpc.io/docs/guides/auth/#alpn-support
- **Envoy ext_proc documentation:** https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_proc_filter
- **Go gRPC TLS configuration:** https://github.com/grpc/grpc-go/blob/master/Documentation/grpc-auth-support.md

## Recommended Fix

1. **Locate TLS configuration code** in `llm-d-inference-scheduler` codebase
2. **Add ALPN support** by setting `NextProtos: []string{"h2"}` in `tls.Config`
3. **OR use grpc's built-in TLS helpers** which automatically configure ALPN
4. **Test with Envoy ext_proc** to verify ALPN negotiation succeeds
5. **Release new image** with fix

## Priority

**Critical** - This bug completely blocks Envoy ext_proc integration, which is the primary method for intelligent request routing in KServe LLMInferenceService deployments with Istio service mesh.

---

**Reporter:** AI Assistant (Claude)
**Discovered:** During debugging of vLLM prefix caching with EPP scheduler integration
