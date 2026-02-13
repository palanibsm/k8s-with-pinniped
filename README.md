# Bare Metal Kubernetes Cluster Setup

Production-ready Kubernetes cluster setup for 4 bare metal servers with high availability.

## 🏗️ Architecture

### Cluster Configuration
- **3 Master + Worker Nodes**: Control plane with workload capability
- **1 Dedicated Worker Node**: Application workloads only
- **Total: 4 bare metal servers**

### Component Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Container Runtime** | containerd | Lightweight, Kubernetes-native runtime |
| **CNI Plugin** | Cilium | eBPF-based networking with advanced features |
| **Control Plane LB** | HAProxy + Keepalived | HA load balancer with VIP failover |
| **Service LB** | MetalLB | LoadBalancer IPs for bare metal |
| **Storage** | Local Path Provisioner | Dynamic local volume provisioning |
| **Ingress** | NGINX Ingress Controller | HTTP/HTTPS routing |
| **Certificates** | cert-manager | Automatic TLS certificate management |
| **Authentication** | Pinniped + Azure AD | Enterprise SSO and RBAC |
| **Monitoring** | Prometheus + Grafana | Metrics and dashboards |
| **Observability** | Cilium Hubble | Network observability |
| **Registry** | Harbor | Private container registry |

## 📁 Directory Structure

```
k8s/
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml              # Inventory file
│   │   └── group_vars/
│   │       └── all.yml            # Global variables
│   ├── playbooks/
│   │   ├── 01-prerequisites.yml   # OS setup, swap disable, etc.
│   │   ├── 02-container-runtime.yml # containerd installation
│   │   ├── 03-kubernetes.yml      # kubeadm, kubelet, kubectl
│   │   ├── 04-haproxy-keepalived.yml # Control plane LB
│   │   ├── 05-init-control-plane.yml # Initialize first master
│   │   ├── 06-join-masters.yml    # Join additional masters
│   │   ├── 07-join-workers.yml    # Join worker nodes
│   │   ├── 08-cilium.yml          # Install Cilium CNI
│   │   ├── 09-metallb.yml         # Install MetalLB
│   │   ├── 10-storage.yml         # Local Path Provisioner
│   │   ├── 11-ingress.yml         # NGINX Ingress
│   │   ├── 12-cert-manager.yml    # cert-manager
│   │   ├── 13-monitoring.yml      # Prometheus & Grafana
│   │   ├── 14-harbor.yml          # Harbor registry
│   │   ├── 15-pinniped-supervisor.yml # Pinniped Supervisor (OIDC)
│   │   ├── 16-pinniped-concierge.yml  # Pinniped Concierge (Auth)
│   │   └── 17-pinniped-rbac.yml   # Azure AD RBAC mapping
│   ├── roles/                     # Ansible roles (if needed)
│   └── ansible.cfg                # Ansible configuration
├── configs/
│   ├── cilium/                    # Cilium configurations
│   ├── metallb/                   # MetalLB configurations
│   ├── ingress/                   # Ingress configurations
│   ├── monitoring/                # Monitoring configurations
│   ├── harbor/                    # Harbor configurations
│   └── pinniped/                  # Pinniped & Azure AD configs
├── docs/
│   ├── INSTALLATION.md            # Step-by-step guide
│   ├── ARCHITECTURE.md            # Detailed architecture
│   ├── TROUBLESHOOTING.md         # Common issues
│   ├── POST-INSTALL.md            # Post-installation tasks
│   ├── AZURE-AD-CONFIGURATION.md  # Azure AD setup
│   ├── PINNIPED-SETUP.md          # Pinniped integration
│   └── USER-ONBOARDING.md         # User access guide
└── scripts/
    ├── verify-prerequisites.sh    # Verify node requirements
    ├── health-check.sh            # Cluster health check
    ├── install-pinniped-cli.sh    # Install Pinniped CLI
    └── configure-pinniped-auth.sh # Configure kubectl auth
```

## 🚀 Quick Start

### Prerequisites
- 4 bare metal servers meeting hardware requirements
- SSH access to all servers
- Ansible installed on your control machine
- Static IP addresses assigned to all nodes

### Installation Steps

1. **Update inventory file**
   ```bash
   cd ansible/inventory
   # Edit hosts.yml with your server IPs
   ```

2. **Configure variables**
   ```bash
   cd ansible/inventory/group_vars
   # Edit all.yml with your network settings
   ```

3. **Run playbooks in order**
   ```bash
   cd ansible
   ansible-playbook -i inventory/hosts.yml playbooks/01-prerequisites.yml
   ansible-playbook -i inventory/hosts.yml playbooks/02-container-runtime.yml
   # Continue with remaining playbooks...
   ```

See [docs/INSTALLATION.md](docs/INSTALLATION.md) for detailed instructions.

## 📊 Cluster Access

After installation:
- **Kubernetes API**: `https://<VIP>:6443`
- **Grafana**: `https://grafana.<your-domain>`
- **Harbor**: `https://harbor.<your-domain>`
- **Hubble UI**: `https://hubble.<your-domain>`

## 🔒 Security Features

- Network policies via Cilium
- TLS everywhere with cert-manager
- RBAC enabled by default
- Harbor vulnerability scanning
- Encrypted etcd

## 📚 Documentation

- [Installation Guide](docs/INSTALLATION.md)
- [Architecture Details](docs/ARCHITECTURE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Post-Installation](docs/POST-INSTALL.md)

## 🤝 Support

For issues or questions, refer to the troubleshooting guide or check component documentation.

---

**Status**: Ready for deployment
**Last Updated**: 2026-02-13
