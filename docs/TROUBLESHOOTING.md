# Troubleshooting Guide

Common issues and solutions for bare metal Kubernetes cluster.

## Table of Contents
- [Node Issues](#node-issues)
- [Network Issues](#network-issues)
- [Storage Issues](#storage-issues)
- [Pod Issues](#pod-issues)
- [Component-Specific Issues](#component-specific-issues)

## Node Issues

### Nodes Not Ready

**Symptoms:**
```bash
kubectl get nodes
# Shows nodes in NotReady state
```

**Possible Causes & Solutions:**

1. **CNI not installed or not working**
   ```bash
   # Check Cilium pods
   kubectl get pods -n kube-system -l k8s-app=cilium

   # Check Cilium status
   cilium status

   # Restart Cilium if needed
   kubectl rollout restart daemonset/cilium -n kube-system
   ```

2. **kubelet not running**
   ```bash
   # On the affected node
   systemctl status kubelet
   systemctl restart kubelet

   # Check kubelet logs
   journalctl -u kubelet -f
   ```

3. **Container runtime issues**
   ```bash
   # Check containerd
   systemctl status containerd

   # Restart if needed
   systemctl restart containerd
   ```

### Node Not Joining Cluster

**Check join token:**
```bash
# On control plane
kubeadm token list

# Create new token if expired
kubeadm token create --print-join-command
```

**Check network connectivity:**
```bash
# From worker, test control plane API
curl -k https://<control-plane-vip>:6443

# Check if all required ports are open
nc -zv <control-plane-ip> 6443
nc -zv <control-plane-ip> 10250
```

## Network Issues

### Pods Cannot Communicate

**Check Cilium:**
```bash
# Verify Cilium is running
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium connectivity
cilium connectivity test

# Check cilium endpoints
kubectl exec -n kube-system <cilium-pod> -- cilium endpoint list
```

**Check Network Policies:**
```bash
# List network policies
kubectl get networkpolicies -A

# Describe specific policy
kubectl describe networkpolicy <policy-name> -n <namespace>
```

### DNS Not Working

**Test DNS:**
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

**Check CoreDNS:**
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### LoadBalancer IP Not Assigned

**Check MetalLB:**
```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check speaker logs
kubectl logs -n metallb-system -l component=speaker

# Check IPAddressPool
kubectl get ipaddresspool -n metallb-system
```

### Ingress Not Working

**Check NGINX Ingress:**
```bash
# Check ingress controller pods
kubectl get pods -n ingress-nginx

# Check controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Describe ingress resource
kubectl describe ingress <ingress-name> -n <namespace>
```

**Test with curl:**
```bash
# Get Ingress IP
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test with Host header
curl -H "Host: your-domain.com" http://$INGRESS_IP
```

## Storage Issues

### PVC Not Binding

**Check StorageClass:**
```bash
kubectl get storageclass
kubectl describe storageclass local-path
```

**Check provisioner:**
```bash
kubectl get pods -n local-path-storage
kubectl logs -n local-path-storage -l app=local-path-provisioner
```

**Check PVC details:**
```bash
kubectl describe pvc <pvc-name> -n <namespace>
```

### Storage Path Issues

**Verify storage directory exists on nodes:**
```bash
ansible -i inventory/hosts.yml all -a "ls -la /opt/local-path-provisioner"
```

## Pod Issues

### Pods Pending

**Check events:**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Common causes:**
- Insufficient resources
- Node selector/taints
- PVC not binding
- Image pull issues

### Pods CrashLoopBackOff

**Check logs:**
```bash
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container
```

**Check resource limits:**
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 Limits
```

### ImagePullBackOff

**Check image name:**
```bash
kubectl describe pod <pod-name> -n <namespace> | grep Image
```

**Check image pull secrets:**
```bash
kubectl get secrets -n <namespace>
kubectl describe secret <secret-name> -n <namespace>
```

**For Harbor registry:**
```bash
# Create docker-registry secret
kubectl create secret docker-registry harbor-registry \
  --docker-server=harbor.your-domain.com \
  --docker-username=admin \
  --docker-password=<password>
```

## Component-Specific Issues

### HAProxy/Keepalived Issues

**Check VIP:**
```bash
# On master nodes
ip addr show | grep <vip>

# Check Keepalived
systemctl status keepalived
journalctl -u keepalived -f

# Check HAProxy
systemctl status haproxy
journalctl -u haproxy -f
```

**HAProxy stats page:**
```bash
curl http://<master-ip>:9000/stats
```

### Cilium Issues

**Check status:**
```bash
cilium status --wait

# Detailed connectivity check
cilium connectivity test
```

**Check Hubble:**
```bash
kubectl get pods -n kube-system -l k8s-app=hubble

# Port-forward to access Hubble UI
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
```

### cert-manager Issues

**Check cert-manager pods:**
```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager
```

**Check certificate status:**
```bash
kubectl get certificate -A
kubectl describe certificate <cert-name> -n <namespace>

# Check certificate request
kubectl get certificaterequest -A
```

**Check ClusterIssuer:**
```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

### Monitoring Issues

**Prometheus not scraping:**
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Navigate to http://localhost:9090/targets
```

**Grafana not accessible:**
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
```

### Harbor Issues

**Harbor pods not starting:**
```bash
kubectl get pods -n harbor
kubectl logs -n harbor <pod-name>
```

**Cannot push images:**
```bash
# Check Harbor core logs
kubectl logs -n harbor -l component=core

# Verify TLS certificate
kubectl get certificate -n harbor
```

## General Debugging Commands

### Cluster Status
```bash
# Node status
kubectl get nodes -o wide

# Pod status across all namespaces
kubectl get pods -A -o wide

# All resources
kubectl get all -A

# Events
kubectl get events -A --sort-by='.lastTimestamp'
```

### Component Health
```bash
# Control plane components
kubectl get componentstatuses

# API server
kubectl cluster-info

# etcd health
kubectl exec -n kube-system etcd-<master-node> -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key endpoint health
```

### Resource Usage
```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -A
```

### Network Debugging
```bash
# Create debug pod
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash

# Inside debug pod:
# - Test DNS: nslookup kubernetes.default
# - Test connectivity: ping <pod-ip>
# - Trace route: traceroute <ip>
# - Check ports: nc -zv <ip> <port>
```

## Getting Help

1. **Check logs**: Start with pod logs and events
2. **Describe resources**: Use `kubectl describe` for detailed info
3. **Component status**: Verify all components are running
4. **Network connectivity**: Test network between components
5. **Resource constraints**: Check if nodes have sufficient resources

## Useful Commands

```bash
# Delete stuck namespace
kubectl get namespace <namespace> -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/<namespace>/finalize" -f -

# Force delete pod
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force

# Get pod YAML
kubectl get pod <pod-name> -n <namespace> -o yaml

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# Copy files to/from pod
kubectl cp <pod-name>:/path/to/file /local/path -n <namespace>
kubectl cp /local/path <pod-name>:/path/to/file -n <namespace>
```
