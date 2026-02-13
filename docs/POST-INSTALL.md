# Post-Installation Tasks

Additional configuration and best practices after cluster installation.

## Table of Contents
- [Security Hardening](#security-hardening)
- [Backup and Disaster Recovery](#backup-and-disaster-recovery)
- [Monitoring and Alerting](#monitoring-and-alerting)
- [Resource Management](#resource-management)
- [Application Deployment](#application-deployment)

## Security Hardening

### 1. Change Default Passwords

```bash
# Grafana admin password
kubectl exec -n monitoring \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -- grafana-cli admin reset-admin-password <NewPassword>

# Harbor admin password - Change through web UI:
# 1. Login to https://harbor.your-domain.com
# 2. Click Admin (top right)
# 3. Change Password

# HAProxy stats password
# Edit the playbook or manually update on each master node:
ansible -i inventory/hosts.yml loadbalancer -m lineinfile \
  -a "path=/etc/haproxy/haproxy.cfg regexp='stats auth' line='    stats auth admin:<NewPassword>'"
ansible -i inventory/hosts.yml loadbalancer -a "systemctl reload haproxy"
```

### 2. Enable RBAC Policies

Create namespace-specific roles:

```yaml
# developer-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: myapp
rules:
- apiGroups: ["", "apps", "batch"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: myapp
subjects:
- kind: User
  name: developer@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

### 3. Pod Security Standards

Enable Pod Security Admission:

```yaml
# pod-security-policy.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 4. Network Policies

Create default deny policy:

```yaml
# default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: myapp
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: myapp
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

### 5. Image Security with Harbor

Enable vulnerability scanning:

```bash
# In Harbor UI:
# 1. Go to Projects -> library
# 2. Configuration -> Enable vulnerability scanning
# 3. Set scan trigger to "Scan on Push"
```

## Backup and Disaster Recovery

### 1. Install Velero for Cluster Backups

```bash
# Download Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xvf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# Install Velero (using local storage for simplicity)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: velero
EOF

# For production, configure with S3-compatible storage
```

### 2. Backup etcd

Create etcd backup script:

```bash
#!/bin/bash
# backup-etcd.sh
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Keep only last 7 days of backups
find /backup -name "etcd-*.db" -mtime +7 -delete
```

Schedule with cron:
```bash
# Run daily at 2 AM
0 2 * * * /usr/local/bin/backup-etcd.sh
```

### 3. Backup Persistent Volumes

Use Velero or create manual backup scripts:

```bash
# Example: Backup all PVs to NFS
for pv in $(kubectl get pv -o jsonpath='{.items[*].metadata.name}'); do
  rsync -av /opt/local-path-provisioner/${pv}/ /mnt/backup/pvs/${pv}/
done
```

## Monitoring and Alerting

### 1. Configure Prometheus Alerts

Create custom alert rules:

```yaml
# custom-alerts.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-alerts
  namespace: monitoring
data:
  custom-alerts.yaml: |
    groups:
    - name: custom-alerts
      interval: 30s
      rules:
      - alert: HighPodMemory
        expr: sum(container_memory_usage_bytes) by (pod, namespace) > 1e9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage in {{ $labels.namespace }}/{{ $labels.pod }}"

      - alert: NodeDiskSpaceWarning
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Node {{ $labels.instance }} disk space below 20%"
```

### 2. Configure Grafana Dashboards

Import recommended dashboards:
- **Node Exporter Full** (ID: 1860)
- **Kubernetes Cluster Monitoring** (ID: 7249)
- **Cilium Metrics** (ID: 16611)

### 3. Set Up AlertManager

Configure email notifications:

```yaml
# alertmanager-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-kube-prometheus-stack-alertmanager
  namespace: monitoring
type: Opaque
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: 'alertmanager@example.com'
      smtp_auth_username: 'your-email@gmail.com'
      smtp_auth_password: 'your-app-password'

    route:
      group_by: ['alertname', 'cluster']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'email'

    receivers:
    - name: 'email'
      email_configs:
      - to: 'team@example.com'
        send_resolved: true
```

## Resource Management

### 1. Configure Resource Quotas

```yaml
# namespace-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: myapp
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    persistentvolumeclaims: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: myapp
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
```

### 2. Configure Node Affinity

Label nodes for workload placement:

```bash
# Label nodes by purpose
kubectl label nodes worker01 workload-type=production
kubectl label nodes master01 master02 master03 workload-type=system

# Use in deployments
```

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: workload-type
            operator: In
            values:
            - production
```

### 3. Enable Autoscaling

Horizontal Pod Autoscaler:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Application Deployment

### 1. Use Harbor for Images

Push images to Harbor:

```bash
# Login to Harbor
docker login harbor.your-domain.com
# Username: admin
# Password: <your-password>

# Tag and push
docker tag myapp:latest harbor.your-domain.com/library/myapp:latest
docker push harbor.your-domain.com/library/myapp:latest

# Create pull secret
kubectl create secret docker-registry harbor-pull-secret \
  --docker-server=harbor.your-domain.com \
  --docker-username=admin \
  --docker-password=<password> \
  -n myapp
```

### 2. Deploy with Helm

Create Helm chart:

```bash
helm create myapp

# Customize values.yaml
cat > myapp/values.yaml <<EOF
image:
  repository: harbor.your-domain.com/library/myapp
  tag: "1.0.0"
  pullPolicy: IfNotPresent

imagePullSecrets:
  - name: harbor-pull-secret

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: myapp.your-domain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: myapp-tls
      hosts:
        - myapp.your-domain.com

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
EOF

# Deploy
helm install myapp ./myapp -n myapp --create-namespace
```

### 3. CI/CD Integration

Example GitHub Actions workflow:

```yaml
# .github/workflows/deploy.yml
name: Build and Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Build and push to Harbor
      run: |
        docker login harbor.your-domain.com -u admin -p ${{ secrets.HARBOR_PASSWORD }}
        docker build -t harbor.your-domain.com/library/myapp:${{ github.sha }} .
        docker push harbor.your-domain.com/library/myapp:${{ github.sha }}

    - name: Deploy to Kubernetes
      uses: azure/k8s-deploy@v4
      with:
        manifests: |
          k8s/deployment.yaml
        images: |
          harbor.your-domain.com/library/myapp:${{ github.sha }}
        kubeconfig: ${{ secrets.KUBE_CONFIG }}
```

## Maintenance Tasks

### Regular Tasks

**Daily:**
- Check cluster health: `kubectl get nodes`
- Review failed pods: `kubectl get pods -A | grep -v Running`
- Check disk space on nodes

**Weekly:**
- Review Grafana dashboards
- Check for pending updates
- Review Harbor vulnerability scans
- Verify backups are running

**Monthly:**
- Update Kubernetes components
- Review and rotate secrets
- Audit RBAC policies
- Test disaster recovery procedures

### Upgrade Strategy

1. Test upgrades in staging first
2. Upgrade one control plane node at a time
3. Upgrade worker nodes with rolling updates
4. Verify cluster health after each upgrade

```bash
# Upgrade control plane
kubeadm upgrade plan
kubeadm upgrade apply v1.29.x

# Upgrade kubelet
apt-mark unhold kubelet kubectl
apt-get update && apt-get install -y kubelet=1.29.x-1.1 kubectl=1.29.x-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
```

## Useful Tools

- **k9s**: Terminal UI for Kubernetes
- **kubectx/kubens**: Switch between contexts/namespaces
- **stern**: Multi-pod log tailing
- **kube-capacity**: Resource capacity management
- **popeye**: Cluster sanitizer

```bash
# Install k9s
wget https://github.com/derailed/k9s/releases/download/v0.29.1/k9s_Linux_amd64.tar.gz
tar -xzf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/local/bin/
```

## Next Steps

1. Implement automated testing
2. Set up log aggregation (ELK/Loki)
3. Configure service mesh (Istio/Linkerd) if needed
4. Implement GitOps with ArgoCD/Flux
5. Set up disaster recovery drills
