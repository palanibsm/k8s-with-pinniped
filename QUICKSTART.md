# Quick Start Guide

Get your bare metal Kubernetes cluster up and running in 3-4 hours.

## Prerequisites

- **4 bare metal servers** with OS installed (Ubuntu 20.04+ or RHEL 8+)
- **SSH access** to all servers
- **Ansible** installed on your control machine
- **Static IP addresses** assigned

## 1. Configure Your Environment (15 minutes)

### Update Inventory

Edit [`ansible/inventory/hosts.yml`](ansible/inventory/hosts.yml):

```yaml
master01:
  ansible_host: 192.168.1.101  # ← CHANGE THIS
  node_ip: 192.168.1.101
  node_name: master01

# Update all 4 nodes
```

### Update Variables

Edit [`ansible/inventory/group_vars/all.yml`](ansible/inventory/group_vars/all.yml):

```yaml
# REQUIRED CHANGES:
control_plane_vip: "192.168.1.100"           # ← Available IP for VIP
base_domain: "k8s.example.com"               # ← Your domain
metallb_ip_range: "192.168.1.200-192.168.1.250"  # ← Available IPs
keepalived_interface: "eth0"                 # ← Your network interface
cert_manager_email: "admin@example.com"      # ← Your email

# SECURITY - Change these passwords:
grafana_admin_password: "changeme"           # ← Change this
harbor_admin_password: "changeme"            # ← Change this
haproxy_stats_password: "changeme"           # ← Change this
keepalived_auth_pass: "changeme"             # ← Change this
```

### Test Connectivity

```bash
cd ansible
ansible -i inventory/hosts.yml all -m ping
```

## 2. Run Installation (2-3 hours)

### Option A: Run All at Once (recommended)

```bash
cd ansible

# Run all playbooks sequentially
for playbook in playbooks/*.yml; do
    echo "Running $playbook..."
    ansible-playbook -i inventory/hosts.yml "$playbook"
done
```

### Option B: Run Step by Step

```bash
cd ansible

# Phase 1: Prerequisites (15 min)
ansible-playbook -i inventory/hosts.yml playbooks/01-prerequisites.yml

# Phase 2: Container Runtime (10 min)
ansible-playbook -i inventory/hosts.yml playbooks/02-container-runtime.yml

# Phase 3: Kubernetes (10 min)
ansible-playbook -i inventory/hosts.yml playbooks/03-kubernetes.yml

# Phase 4: Load Balancer (10 min)
ansible-playbook -i inventory/hosts.yml playbooks/04-haproxy-keepalived.yml

# Phase 5: Initialize Control Plane (10 min)
ansible-playbook -i inventory/hosts.yml playbooks/05-init-control-plane.yml

# Phase 6: Join Masters (10 min)
ansible-playbook -i inventory/hosts.yml playbooks/06-join-masters.yml

# Phase 7: Join Workers (5 min)
ansible-playbook -i inventory/hosts.yml playbooks/07-join-workers.yml

# Phase 8: Install Cilium CNI (15 min)
ansible-playbook -i inventory/hosts.yml playbooks/08-cilium.yml

# Phase 9: Install MetalLB (10 min)
ansible-playbook -i inventory/hosts.yml playbooks/09-metallb.yml

# Phase 10: Install Storage (10 min)
ansible-playbook -i inventory/hosts.yml playbooks/10-storage.yml

# Phase 11: Install Ingress (10 min)
ansible-playbook -i inventory/hosts.yml playbooks/11-ingress.yml

# Phase 12: Install cert-manager (10 min)
ansible-playbook -i inventory/hosts.yml playbooks/12-cert-manager.yml

# Phase 13: Install Monitoring (15 min)
ansible-playbook -i inventory/hosts.yml playbooks/13-monitoring.yml

# Phase 14: Install Harbor (15 min)
ansible-playbook -i inventory/hosts.yml playbooks/14-harbor.yml
```

## 3. Configure kubectl (5 minutes)

```bash
# The kubeconfig was saved during installation
export KUBECONFIG=$(pwd)/configs/kubeconfig

# Test access
kubectl get nodes
kubectl get pods -A
```

## 4. Configure DNS (10 minutes)

Get the Ingress IP:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
# Note the EXTERNAL-IP
```

Add DNS A records (or update `/etc/hosts`):

```
<INGRESS-IP>  grafana.k8s.example.com
<INGRESS-IP>  prometheus.k8s.example.com
<INGRESS-IP>  harbor.k8s.example.com
<INGRESS-IP>  hubble.k8s.example.com
<INGRESS-IP>  *.k8s.example.com
```

## 5. Access Services

### Grafana
- URL: `https://grafana.k8s.example.com`
- Username: `admin`
- Password: (from all.yml)

### Prometheus
- URL: `https://prometheus.k8s.example.com`

### Harbor
- URL: `https://harbor.k8s.example.com`
- Username: `admin`
- Password: (from all.yml)

### Hubble UI (Network Observability)
- URL: `https://hubble.k8s.example.com`

## 6. Verify Installation

Run the health check script:

```bash
./scripts/health-check.sh
```

Expected output: All checks should pass ✓

## 7. Deploy Your First App

```bash
# Create namespace
kubectl create namespace myapp

# Create deployment
kubectl create deployment nginx --image=nginx -n myapp

# Expose service
kubectl expose deployment nginx --port=80 -n myapp

# Create ingress
kubectl create ingress nginx \
  --class=nginx \
  --rule="myapp.k8s.example.com/*=nginx:80" \
  --annotation="cert-manager.io/cluster-issuer=letsencrypt-prod" \
  -n myapp

# Wait for certificate
kubectl get certificate -n myapp -w

# Access your app
curl https://myapp.k8s.example.com
```

## Common Issues

### Nodes Not Ready
```bash
# Check Cilium
kubectl get pods -n kube-system -l k8s-app=cilium
cilium status
```

### Can't Access Services
```bash
# Check Ingress
kubectl get svc -n ingress-nginx
kubectl get ingress -A

# Check DNS
nslookup grafana.k8s.example.com
```

### Pods Not Starting
```bash
# Check events
kubectl get events -A --sort-by='.lastTimestamp'

# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Describe pod
kubectl describe pod <pod-name> -n <namespace>
```

## Next Steps

1. **Security**: Change all default passwords
2. **Backups**: Set up etcd and PV backups
3. **Monitoring**: Configure Prometheus alerts
4. **CI/CD**: Set up pipelines with Harbor
5. **Applications**: Deploy your workloads

## Documentation

- 📖 [Full Installation Guide](docs/INSTALLATION.md)
- 🏗️ [Architecture Details](docs/ARCHITECTURE.md)
- 🔧 [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- 🚀 [Post-Installation Tasks](docs/POST-INSTALL.md)

## Support

For detailed documentation and troubleshooting, see the `docs/` directory.

## What You Get

✅ **High Availability**
- 3-node control plane with automatic failover
- etcd cluster with quorum
- Load balanced API server

✅ **Production Components**
- Cilium CNI with eBPF and Hubble
- MetalLB for LoadBalancer services
- NGINX Ingress with automatic TLS
- Local Path storage provisioner

✅ **Monitoring & Registry**
- Prometheus + Grafana + AlertManager
- Harbor container registry with Trivy scanner

✅ **Security**
- cert-manager for automatic TLS certificates
- Network policies ready
- RBAC enabled

## File Structure

```
k8s/
├── ansible/
│   ├── inventory/          # Your server configuration
│   ├── playbooks/          # 14 installation playbooks
│   └── ansible.cfg
├── configs/               # Generated configurations
├── docs/                  # Detailed documentation
├── scripts/               # Helper scripts
└── README.md             # Project overview
```

Happy clustering! 🚀
