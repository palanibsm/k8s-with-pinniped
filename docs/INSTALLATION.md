# Kubernetes Bare Metal Installation Guide

This guide provides step-by-step instructions for installing a production-ready Kubernetes cluster on bare metal servers.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Pre-Installation Checklist](#pre-installation-checklist)
- [Installation Steps](#installation-steps)
- [Post-Installation](#post-installation)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Hardware Requirements

| Component | Requirement |
|-----------|-------------|
| **Master Nodes (3)** | 4+ CPU cores, 8GB+ RAM, 50GB+ disk |
| **Worker Nodes (1)** | 4+ CPU cores, 8GB+ RAM, 100GB+ disk |
| **Network** | Gigabit Ethernet, static IPs |

### Software Requirements

- **OS**: Ubuntu 20.04+, Debian 11+, RHEL 8+, or CentOS 8+
- **SSH Access**: Root or sudo access to all nodes
- **Ansible**: Version 2.10+ on control machine
- **Python**: Python 3.6+ on all nodes

### Network Requirements

- All nodes must be on the same network segment
- Static IP addresses configured on all nodes
- DNS resolution working (or /etc/hosts configured)
- Available IP range for MetalLB LoadBalancer services
- One available IP for control plane VIP (Virtual IP)

## Pre-Installation Checklist

### 1. Prepare Your Environment

```bash
# Clone or navigate to the k8s directory
cd /path/to/k8s

# Install Ansible (if not already installed)
# Ubuntu/Debian:
sudo apt update
sudo apt install ansible -y

# RHEL/CentOS:
sudo dnf install ansible -y
```

### 2. Configure SSH Access

```bash
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096

# Copy SSH key to all nodes
ssh-copy-id root@192.168.1.101  # master01
ssh-copy-id root@192.168.1.102  # master02
ssh-copy-id root@192.168.1.103  # master03
ssh-copy-id root@192.168.1.104  # worker01

# Test SSH access
ssh root@192.168.1.101 'hostname'
```

### 3. Update Inventory File

Edit `ansible/inventory/hosts.yml`:

```yaml
control_plane:
  hosts:
    master01:
      ansible_host: 192.168.1.101  # UPDATE THIS
      node_ip: 192.168.1.101
      node_name: master01
    master02:
      ansible_host: 192.168.1.102  # UPDATE THIS
      node_ip: 192.168.1.102
      node_name: master02
    master03:
      ansible_host: 192.168.1.103  # UPDATE THIS
      node_ip: 192.168.1.103
      node_name: master03

workers:
  hosts:
    worker01:
      ansible_host: 192.168.1.104  # UPDATE THIS
      node_ip: 192.168.1.104
      node_name: worker01
```

### 4. Update Variables

Edit `ansible/inventory/group_vars/all.yml`:

**Critical settings to update:**

```yaml
# Virtual IP for control plane (must be available)
control_plane_vip: "192.168.1.100"  # UPDATE THIS

# Your domain for ingress
base_domain: "k8s.example.com"  # UPDATE THIS

# MetalLB IP range (must be available)
metallb_ip_range: "192.168.1.200-192.168.1.250"  # UPDATE THIS

# Network interface name
keepalived_interface: "eth0"  # UPDATE THIS (use 'ip a' to find)

# Email for Let's Encrypt certificates
cert_manager_email: "admin@example.com"  # UPDATE THIS

# Change default passwords
haproxy_stats_password: "changeme"  # UPDATE THIS
grafana_admin_password: "changeme"  # UPDATE THIS
harbor_admin_password: "changeme"  # UPDATE THIS
keepalived_auth_pass: "changeme"  # UPDATE THIS
```

### 5. Verify Configuration

```bash
cd ansible

# Test Ansible connectivity
ansible -i inventory/hosts.yml all -m ping

# Expected output: All hosts should return SUCCESS
```

## Installation Steps

### Phase 1: Prerequisites and OS Setup (15-20 minutes)

```bash
cd ansible

# Run prerequisites playbook
ansible-playbook -i inventory/hosts.yml playbooks/01-prerequisites.yml
```

**What it does:**
- Disables swap
- Configures kernel modules and sysctl parameters
- Installs required packages
- Configures firewall
- Sets up time synchronization

**Verification:**
```bash
# Check swap is disabled on all nodes
ansible -i inventory/hosts.yml all -a "swapon -s"
# Output should be empty

# Check kernel modules
ansible -i inventory/hosts.yml all -a "lsmod | grep br_netfilter"
# Should show br_netfilter module
```

### Phase 2: Container Runtime (10-15 minutes)

```bash
# Install containerd
ansible-playbook -i inventory/hosts.yml playbooks/02-container-runtime.yml
```

**What it does:**
- Installs containerd
- Installs runc and CNI plugins
- Configures systemd cgroup driver

**Verification:**
```bash
# Check containerd is running
ansible -i inventory/hosts.yml all -a "systemctl status containerd"

# Check ctr version
ansible -i inventory/hosts.yml all -a "ctr version"
```

### Phase 3: Kubernetes Components (10-15 minutes)

```bash
# Install kubeadm, kubelet, kubectl
ansible-playbook -i inventory/hosts.yml playbooks/03-kubernetes.yml
```

**What it does:**
- Installs Kubernetes packages
- Configures kubelet
- Installs crictl

**Verification:**
```bash
# Check kubeadm version
ansible -i inventory/hosts.yml all -a "kubeadm version"

# Check kubectl version
ansible -i inventory/hosts.yml all -a "kubectl version --client"
```

### Phase 4: Control Plane Load Balancer (10 minutes)

```bash
# Install HAProxy and Keepalived
ansible-playbook -i inventory/hosts.yml playbooks/04-haproxy-keepalived.yml
```

**What it does:**
- Installs HAProxy for load balancing
- Installs Keepalived for VIP failover
- Configures health checks

**Verification:**
```bash
# Check if VIP is accessible
ping -c 3 192.168.1.100  # Your VIP

# Check HAProxy stats page (if accessible)
curl http://master01:9000/stats
```

### Phase 5: Initialize Control Plane (10-15 minutes)

```bash
# Initialize first master node
ansible-playbook -i inventory/hosts.yml playbooks/05-init-control-plane.yml
```

**What it does:**
- Initializes Kubernetes cluster
- Generates join tokens
- Configures kubectl access
- Saves kubeconfig locally

**Verification:**
```bash
# Check cluster is accessible
export KUBECONFIG=../configs/kubeconfig
kubectl get nodes

# Should show master01 (but NotReady without CNI)
```

### Phase 6: Join Additional Masters (10 minutes)

```bash
# Join remaining master nodes
ansible-playbook -i inventory/hosts.yml playbooks/06-join-masters.yml
```

**What it does:**
- Joins master02 and master03 to cluster
- Configures kubectl on all masters
- Labels nodes appropriately

**Verification:**
```bash
kubectl get nodes
# Should show all 3 masters (NotReady without CNI)

kubectl get pods -n kube-system
# Should show control plane components on all masters
```

### Phase 7: Join Worker Nodes (5-10 minutes)

```bash
# Join worker nodes
ansible-playbook -i inventory/hosts.yml playbooks/07-join-workers.yml
```

**What it does:**
- Joins worker nodes to cluster
- Labels worker nodes

**Verification:**
```bash
kubectl get nodes -o wide
# Should show all 4 nodes (NotReady without CNI)
```

### Phase 8: Install Cilium CNI (10-15 minutes)

```bash
# Install Cilium networking
ansible-playbook -i inventory/hosts.yml playbooks/08-cilium.yml
```

**What it does:**
- Installs Cilium CLI
- Installs Helm
- Deploys Cilium CNI
- Enables Hubble observability (optional)

**Verification:**
```bash
kubectl get nodes
# All nodes should now show Ready

kubectl get pods -n kube-system -l k8s-app=cilium
# Should show Cilium pods running on all nodes

# Run connectivity test (optional, takes 5-10 minutes)
# cilium connectivity test
```

### Phase 9: Install MetalLB (5-10 minutes)

```bash
# Install MetalLB for LoadBalancer services
ansible-playbook -i inventory/hosts.yml playbooks/09-metallb.yml
```

**What it does:**
- Installs MetalLB
- Configures IP address pool
- Tests LoadBalancer functionality

**Verification:**
```bash
kubectl get pods -n metallb-system
# Should show controller and speaker pods

kubectl get ipaddresspool -n metallb-system
# Should show configured IP pool
```

### Phase 10: Install Storage Provisioner (5-10 minutes)

```bash
# Install Local Path Provisioner
ansible-playbook -i inventory/hosts.yml playbooks/10-storage.yml
```

**What it does:**
- Installs Local Path Provisioner
- Sets it as default StorageClass
- Tests dynamic volume provisioning

**Verification:**
```bash
kubectl get storageclass
# Should show local-path (default)

kubectl get pods -n local-path-storage
# Should show provisioner pod
```

### Phase 11: Install NGINX Ingress (5-10 minutes)

```bash
# Install NGINX Ingress Controller
ansible-playbook -i inventory/hosts.yml playbooks/11-ingress.yml
```

**What it does:**
- Installs NGINX Ingress Controller
- Gets LoadBalancer IP from MetalLB
- Tests Ingress functionality

**Verification:**
```bash
kubectl get pods -n ingress-nginx
# Should show ingress controller pods

kubectl get svc -n ingress-nginx
# Note the EXTERNAL-IP for DNS configuration
```

### Phase 12: Install cert-manager (5-10 minutes)

```bash
# Install cert-manager for automatic TLS
ansible-playbook -i inventory/hosts.yml playbooks/12-cert-manager.yml
```

**What it does:**
- Installs cert-manager
- Creates ClusterIssuers (Let's Encrypt, self-signed)
- Tests certificate issuance

**Verification:**
```bash
kubectl get pods -n cert-manager
# Should show cert-manager pods

kubectl get clusterissuer
# Should show letsencrypt-prod, letsencrypt-staging, selfsigned-issuer
```

### Phase 13: Install Monitoring Stack (10-15 minutes)

```bash
# Install Prometheus and Grafana
ansible-playbook -i inventory/hosts.yml playbooks/13-monitoring.yml
```

**What it does:**
- Installs Prometheus for metrics
- Installs Grafana for visualization
- Installs AlertManager
- Creates Ingress resources

**Verification:**
```bash
kubectl get pods -n monitoring
# Should show Prometheus, Grafana, AlertManager pods

kubectl get pvc -n monitoring
# Should show persistent volume claims
```

### Phase 14: Install Harbor Registry (10-15 minutes)

```bash
# Install Harbor container registry
ansible-playbook -i inventory/hosts.yml playbooks/14-harbor.yml
```

**What it does:**
- Installs Harbor container registry
- Enables Trivy vulnerability scanner
- Creates Ingress for web UI

**Verification:**
```bash
kubectl get pods -n harbor
# Should show Harbor components

kubectl get pvc -n harbor
# Should show storage volumes
```

## Post-Installation

### 1. Configure DNS

Get the Ingress LoadBalancer IP:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Add DNS A records (or /etc/hosts entries):

```
<INGRESS-IP>  grafana.k8s.example.com
<INGRESS-IP>  prometheus.k8s.example.com
<INGRESS-IP>  alertmanager.k8s.example.com
<INGRESS-IP>  harbor.k8s.example.com
<INGRESS-IP>  hubble.k8s.example.com
```

### 2. Access Services

- **Grafana**: https://grafana.your-domain.com
  - Username: `admin`
  - Password: (from all.yml)

- **Prometheus**: https://prometheus.your-domain.com

- **Harbor**: https://harbor.your-domain.com
  - Username: `admin`
  - Password: (from all.yml)

- **Hubble UI** (if enabled): https://hubble.your-domain.com

### 3. Change Default Passwords

```bash
# Change Grafana password
kubectl exec -n monitoring $(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') -- grafana-cli admin reset-admin-password NewPassword

# Change Harbor password through web UI
# Login to Harbor -> Admin -> Change Password
```

### 4. Configure kubectl Locally

```bash
# Copy kubeconfig to your local machine
export KUBECONFIG=~/k8s-config
cp configs/kubeconfig ~/k8s-config

# Test access
kubectl get nodes
kubectl get pods -A
```

### 5. Create Your First Application

```bash
kubectl create namespace myapp
kubectl create deployment nginx --image=nginx --namespace=myapp
kubectl expose deployment nginx --port=80 --namespace=myapp
kubectl create ingress nginx --class=nginx --rule="myapp.example.com/*=nginx:80" --namespace=myapp
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Next Steps

1. Review [POST-INSTALL.md](POST-INSTALL.md) for additional configuration
2. Set up backups with Velero
3. Configure monitoring alerts
4. Implement RBAC policies
5. Set up CI/CD pipelines

## Estimated Total Time

- **Minimal Installation** (Phases 1-8): ~2 hours
- **Full Stack Installation** (All phases): ~3-4 hours

## Support

For issues or questions:
1. Check the troubleshooting guide
2. Review component documentation
3. Check Ansible playbook logs
4. Review pod logs: `kubectl logs <pod-name> -n <namespace>`
