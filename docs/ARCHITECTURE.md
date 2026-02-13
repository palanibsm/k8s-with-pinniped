# Kubernetes Bare Metal Architecture

Detailed architecture documentation for the bare metal Kubernetes cluster.

## Overview

This is a production-ready, highly available Kubernetes cluster designed for bare metal infrastructure with 4 nodes:
- 3 Master nodes (dual-role: control plane + worker)
- 1 Dedicated worker node

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        External Network                          │
│                      (192.168.1.0/24)                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Virtual IP (Keepalived)
                              │ 192.168.1.100:6443
                              │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   ┌────▼────┐         ┌────▼────┐         ┌────▼────┐
   │ Master1 │         │ Master2 │         │ Master3 │
   │HAProxy  │         │HAProxy  │         │HAProxy  │
   │Keepalvd │         │Keepalvd │         │Keepalvd │
   └────┬────┘         └────┬────┘         └────┬────┘
        │                   │                   │
        │  Control Plane (etcd, API, Scheduler) │
        │                   │                   │
   ┌────▼────────────────────▼────────────────▼────┐
   │         Kubernetes API (6443)                  │
   │         etcd cluster (2379-2380)              │
   └───────────────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼────┐     ┌────▼────┐     ┌────▼────┐    ┌─────────┐
   │ Master1 │     │ Master2 │     │ Master3 │    │ Worker1 │
   │ Worker  │     │ Worker  │     │ Worker  │    │         │
   └─────────┘     └─────────┘     └─────────┘    └─────────┘
        │                │                │              │
        └────────────────┴────────────────┴──────────────┘
                         │
                    Cilium CNI
              (Pod Network: 10.244.0.0/16)
```

## Component Architecture

### Control Plane (HA Configuration)

#### 1. Load Balancer Layer

**HAProxy + Keepalived**
- **Purpose**: Provides HA for Kubernetes API server
- **Virtual IP**: Floats between master nodes using VRRP
- **Load Balancing**: Round-robin across all API servers
- **Health Checks**: Active monitoring of API server endpoints

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Master 1   │     │   Master 2   │     │   Master 3   │
│              │     │              │     │              │
│  HAProxy     │     │  HAProxy     │     │  HAProxy     │
│  Priority:100│     │  Priority:99 │     │  Priority:98 │
│              │     │              │     │              │
│  Keepalived  │◄───►│  Keepalived  │◄───►│  Keepalived  │
│  (MASTER)    │     │  (BACKUP)    │     │  (BACKUP)    │
└──────────────┘     └──────────────┘     └──────────────┘
       ▲
       │ VIP: 192.168.1.100
       │
```

#### 2. Control Plane Components

**Running on all master nodes:**

- **kube-apiserver**: REST API for Kubernetes
  - Port: 6443
  - HA: Multiple instances behind VIP

- **kube-controller-manager**: Manages controllers
  - Leader election enabled
  - Only one active at a time

- **kube-scheduler**: Pod scheduling decisions
  - Leader election enabled
  - Only one active at a time

- **etcd**: Distributed key-value store
  - 3-node cluster for quorum
  - Ports: 2379 (client), 2380 (peer)
  - Raft consensus algorithm

### Data Plane (Worker Nodes)

**Running on all nodes (masters + workers):**

- **kubelet**: Node agent
  - Manages pods on the node
  - Port: 10250

- **Container Runtime**: containerd
  - OCI-compliant runtime
  - CRI integration

## Networking

### Cilium CNI

**Architecture:**
```
┌─────────────────────────────────────────────┐
│              Applications                    │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│           Cilium Agent (DaemonSet)          │
│  ┌──────────────────────────────────────┐   │
│  │  eBPF Programs (XDP, TC, Socket)     │   │
│  │  - Fast packet processing            │   │
│  │  - Network policies                  │   │
│  │  - Load balancing                    │   │
│  │  - kube-proxy replacement            │   │
│  └──────────────────────────────────────┘   │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│          Linux Kernel (eBPF)                │
└─────────────────────────────────────────────┘
```

**Features enabled:**
- **IPAM**: Kubernetes host-scope mode
- **kube-proxy replacement**: eBPF-based service load balancing
- **Network Policies**: L3/L4/L7 policy enforcement
- **Hubble**: Network observability and monitoring
- **Encryption**: Optional (WireGuard)

**Network Ranges:**
- **Pod Network**: 10.244.0.0/16
- **Service Network**: 10.96.0.0/12
- **External LoadBalancer**: 192.168.1.200-250 (MetalLB)

### MetalLB

**Purpose**: Provides LoadBalancer type services on bare metal

**Mode**: Layer 2 (ARP)

```
External Request
      │
      ▼
MetalLB Speaker (announces ARP)
      │
      ▼
NGINX Ingress Controller (LoadBalancer Service)
      │
      ▼
Backend Pods
```

### Ingress

**NGINX Ingress Controller**
- **Type**: LoadBalancer (gets IP from MetalLB)
- **Replicas**: 2 (for HA)
- **TLS**: Automatic with cert-manager

```
Internet
    │
    ▼
NGINX Ingress (LB IP: 192.168.1.200)
    │
    ├─► grafana.example.com ──► Grafana Service
    ├─► prometheus.example.com ──► Prometheus Service
    ├─► harbor.example.com ──► Harbor Service
    └─► app.example.com ──► Application Service
```

## Storage Architecture

### Local Path Provisioner

**Architecture:**
```
┌──────────────────────────────────────────┐
│          PersistentVolumeClaim           │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│     Local Path Provisioner               │
│  - Dynamic PV creation                   │
│  - Node-local storage                    │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│  Node Local Storage                      │
│  /opt/local-path-provisioner/            │
│    ├─ pvc-xxxxx/                        │
│    ├─ pvc-yyyyy/                        │
│    └─ pvc-zzzzz/                        │
└──────────────────────────────────────────┘
```

**Characteristics:**
- **Type**: hostPath-based
- **Performance**: Direct disk I/O (fastest)
- **Availability**: Node-local (not replicated)
- **Use cases**: Databases, caches, ephemeral data

**Storage Paths:**
- **Base path**: `/opt/local-path-provisioner`
- **PV naming**: `pvc-<uuid>`

## Security Architecture

### Certificate Management

**cert-manager**
```
┌─────────────────────────────────────────┐
│        Ingress (with TLS annotation)    │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│          cert-manager                   │
│  ┌──────────────────────────────────┐   │
│  │  Certificate Controller          │   │
│  │  - Watches Ingress resources     │   │
│  │  - Issues certificates           │   │
│  │  - Renews before expiration      │   │
│  └──────────────────────────────────┘   │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│       ClusterIssuer (ACME)              │
│  - Let's Encrypt (Staging/Prod)         │
│  - HTTP-01 challenge via Ingress        │
└─────────────────────────────────────────┘
```

**Certificate Issuers:**
1. **letsencrypt-prod**: Production Let's Encrypt
2. **letsencrypt-staging**: Testing Let's Encrypt
3. **selfsigned-issuer**: Internal certificates

### Network Security

**Security Layers:**
1. **Firewall**: OS-level (firewalld/UFW)
2. **Network Policies**: Cilium L3/L4/L7 policies
3. **TLS**: All external traffic encrypted
4. **RBAC**: Kubernetes role-based access control

## Monitoring Architecture

### Prometheus Stack

```
┌──────────────────────────────────────────────┐
│              Applications                     │
│        (exposing /metrics endpoints)          │
└────────────┬─────────────────────────────────┘
             │
┌────────────▼─────────────────────────────────┐
│         Prometheus                            │
│  ┌───────────────────────────────────────┐   │
│  │  Service Discovery                    │   │
│  │  - Kubernetes SD                      │   │
│  │  - Automatic target discovery         │   │
│  └───────────────────────────────────────┘   │
│  ┌───────────────────────────────────────┐   │
│  │  TSDB (Time Series Database)          │   │
│  │  - Metrics storage (30 days)          │   │
│  │  - 50Gi persistent volume             │   │
│  └───────────────────────────────────────┘   │
└────────────┬─────────────────────────────────┘
             │
     ┌───────┴────────┐
     │                │
┌────▼────┐    ┌─────▼──────┐
│ Grafana │    │AlertManager│
│         │    │            │
│Dashboards│    │   Alerts   │
└─────────┘    └────────────┘
```

**Monitored Components:**
- **Node metrics**: CPU, memory, disk, network (node-exporter)
- **Kubernetes metrics**: Pods, deployments, services (kube-state-metrics)
- **Application metrics**: Custom metrics from apps
- **Cilium metrics**: Network performance and policies
- **System metrics**: Control plane components

## Registry Architecture

### Harbor

```
┌─────────────────────────────────────────┐
│          Docker Client / kubectl        │
└────────────────┬────────────────────────┘
                 │ HTTPS (TLS)
┌────────────────▼────────────────────────┐
│         NGINX Ingress                   │
│    harbor.example.com                   │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│            Harbor Core                  │
│  ┌──────────────────────────────────┐   │
│  │  - Registry API                  │   │
│  │  - Authentication & RBAC         │   │
│  │  - Project Management            │   │
│  │  - Replication                   │   │
│  └──────────────────────────────────┘   │
└───┬────────────────────────────┬────────┘
    │                            │
┌───▼─────────┐          ┌──────▼──────┐
│   Registry  │          │   Trivy     │
│   Storage   │          │  Scanner    │
│ (100Gi PV)  │          │             │
└─────────────┘          └─────────────┘
         │
    ┌────▼─────┐
    │PostgreSQL│
    │  (10Gi)  │
    └──────────┘
```

**Features:**
- **Image storage**: OCI-compliant registry
- **Vulnerability scanning**: Trivy integration
- **RBAC**: Project-based access control
- **Helm charts**: ChartMuseum integration
- **Replication**: Multi-registry sync (optional)

## High Availability

### Failure Scenarios

| Component | Failure Impact | Recovery |
|-----------|---------------|----------|
| **1 Master node** | No impact - API accessible via VIP | Automatic failover |
| **2 Master nodes** | Degraded - etcd has quorum | Manual intervention needed |
| **All masters** | Complete control plane failure | Restore from backup |
| **Worker node** | Pods rescheduled to other nodes | Automatic (if replicas > 1) |
| **Network** | Isolated node marked NotReady | Automatic recovery on reconnect |
| **Storage** | PV unavailable on failed node | Manual PV migration |

### Redundancy

- **Control Plane**: 3 nodes (quorum-based)
- **etcd**: 3-member cluster (survives 1 failure)
- **API Server**: 3 instances behind VIP
- **Ingress Controller**: 2 replicas
- **MetalLB Speakers**: DaemonSet (all nodes)
- **Cilium**: DaemonSet (all nodes)

## Resource Allocation

### Control Plane Resources

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|-----------|--------------|
| etcd | 100m | 100Mi | - | - |
| kube-apiserver | 250m | 128Mi | - | - |
| kube-controller | 200m | 128Mi | - | - |
| kube-scheduler | 100m | 64Mi | - | - |

### Add-on Resources

| Component | CPU Request | Memory Request | Storage |
|-----------|-------------|----------------|---------|
| Cilium | 100m | 128Mi | - |
| MetalLB | 50m | 64Mi | - |
| NGINX Ingress | 100m | 128Mi | - |
| Prometheus | 500m | 2Gi | 50Gi |
| Grafana | 100m | 256Mi | 10Gi |
| Harbor | 200m | 512Mi | 100Gi |

## Scalability

### Current Capacity
- **Nodes**: 4 (can scale to 100+)
- **Pods per node**: 110 (default)
- **Total pods**: ~440
- **Services**: ~5000 (theoretical)

### Scaling Options
1. **Horizontal**: Add more worker nodes
2. **Vertical**: Increase node resources
3. **Control plane**: Add more masters for larger clusters

## Performance Considerations

### Network Performance
- **Cilium eBPF**: Near-native network performance
- **kube-proxy replacement**: Reduced latency
- **MTU**: 1500 (adjust if using overlay networks)

### Storage Performance
- **Local storage**: Direct disk I/O
- **IOPS**: Limited by disk type (SSD recommended)

### Monitoring Performance
- **Prometheus cardinality**: Monitor metric count
- **Grafana queries**: Use efficient queries
- **Log aggregation**: Consider ELK/Loki for logs

## Disaster Recovery

### Backup Strategy
1. **etcd**: Snapshot every 6 hours
2. **Persistent Volumes**: Daily rsync to backup location
3. **Configurations**: GitOps repository
4. **Secrets**: Encrypted backup

### Recovery Time Objectives
- **etcd restore**: 15-30 minutes
- **PV restore**: 30-60 minutes (depends on size)
- **Full cluster rebuild**: 2-4 hours

## Maintenance Windows

### Rolling Updates
- **Zero downtime** for applications with replicas > 1
- **Control plane updates**: One node at a time
- **Worker updates**: Drain, update, uncordon

### Update Schedule
- **Security patches**: Monthly
- **Kubernetes version**: Every 3-4 minor versions
- **Component updates**: Quarterly
