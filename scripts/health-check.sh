#!/bin/bash
# Kubernetes Cluster Health Check Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Kubernetes Cluster Health Check"
echo "=========================================="
echo ""

# Check if kubectl is configured
if ! kubectl version --client &>/dev/null; then
    echo -e "${RED}✗${NC} kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connectivity
echo -e "${BLUE}Checking cluster connectivity...${NC}"
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓${NC} Cluster is reachable"
else
    echo -e "${RED}✗${NC} Cannot connect to cluster"
    exit 1
fi

# Check nodes
echo ""
echo -e "${BLUE}Checking nodes...${NC}"
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)

if [ "$NODE_COUNT" -eq 0 ]; then
    echo -e "${RED}✗${NC} No nodes found"
    exit 1
else
    echo -e "${GREEN}✓${NC} Total nodes: $NODE_COUNT"
    if [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
        echo -e "${GREEN}✓${NC} All nodes are Ready"
    else
        echo -e "${YELLOW}⚠${NC} Ready nodes: $READY_NODES/$NODE_COUNT"
        echo ""
        kubectl get nodes
    fi
fi

# Check control plane components
echo ""
echo -e "${BLUE}Checking control plane components...${NC}"

check_component() {
    local component=$1
    local namespace=$2
    local count=$(kubectl get pods -n "$namespace" -l "$component" --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    local expected=$3

    if [ "$count" -ge "$expected" ]; then
        echo -e "${GREEN}✓${NC} $component: $count/$expected pods running"
        return 0
    else
        echo -e "${RED}✗${NC} $component: $count/$expected pods running"
        return 1
    fi
}

check_component "component=kube-apiserver" "kube-system" 1
check_component "component=kube-controller-manager" "kube-system" 1
check_component "component=kube-scheduler" "kube-system" 1
check_component "component=etcd" "kube-system" 1

# Check CNI (Cilium)
echo ""
echo -e "${BLUE}Checking CNI (Cilium)...${NC}"
CILIUM_PODS=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | wc -l)
CILIUM_RUNNING=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep -c "Running" || echo 0)

if [ "$CILIUM_RUNNING" -ge 1 ]; then
    echo -e "${GREEN}✓${NC} Cilium: $CILIUM_RUNNING/$CILIUM_PODS pods running"
else
    echo -e "${RED}✗${NC} Cilium: $CILIUM_RUNNING/$CILIUM_PODS pods running"
fi

# Check MetalLB
echo ""
echo -e "${BLUE}Checking MetalLB...${NC}"
if kubectl get namespace metallb-system &>/dev/null; then
    METALLB_CONTROLLER=$(kubectl get pods -n metallb-system -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    METALLB_SPEAKER=$(kubectl get pods -n metallb-system -l app.kubernetes.io/component=speaker --no-headers 2>/dev/null | grep -c "Running" || echo 0)

    if [ "$METALLB_CONTROLLER" -ge 1 ]; then
        echo -e "${GREEN}✓${NC} MetalLB Controller: Running"
    else
        echo -e "${RED}✗${NC} MetalLB Controller: Not running"
    fi

    if [ "$METALLB_SPEAKER" -ge 1 ]; then
        echo -e "${GREEN}✓${NC} MetalLB Speaker: $METALLB_SPEAKER pods running"
    else
        echo -e "${RED}✗${NC} MetalLB Speaker: Not running"
    fi
else
    echo -e "${YELLOW}⚠${NC} MetalLB namespace not found (not installed?)"
fi

# Check Ingress
echo ""
echo -e "${BLUE}Checking NGINX Ingress...${NC}"
if kubectl get namespace ingress-nginx &>/dev/null; then
    INGRESS_PODS=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ "$INGRESS_PODS" -ge 1 ]; then
        echo -e "${GREEN}✓${NC} NGINX Ingress: $INGRESS_PODS pods running"
    else
        echo -e "${RED}✗${NC} NGINX Ingress: Not running"
    fi

    if [ -n "$INGRESS_IP" ]; then
        echo -e "${GREEN}✓${NC} Ingress LoadBalancer IP: $INGRESS_IP"
    else
        echo -e "${YELLOW}⚠${NC} Ingress LoadBalancer IP not assigned"
    fi
else
    echo -e "${YELLOW}⚠${NC} Ingress namespace not found (not installed?)"
fi

# Check Storage
echo ""
echo -e "${BLUE}Checking Storage...${NC}"
STORAGE_CLASS=$(kubectl get storageclass --no-headers 2>/dev/null | grep -c "(default)" || echo 0)
if [ "$STORAGE_CLASS" -ge 1 ]; then
    DEFAULT_SC=$(kubectl get storageclass --no-headers 2>/dev/null | grep "(default)" | awk '{print $1}')
    echo -e "${GREEN}✓${NC} Default StorageClass: $DEFAULT_SC"
else
    echo -e "${YELLOW}⚠${NC} No default StorageClass found"
fi

# Check cert-manager
echo ""
echo -e "${BLUE}Checking cert-manager...${NC}"
if kubectl get namespace cert-manager &>/dev/null; then
    CERTMGR_PODS=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    CERTMGR_TOTAL=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l)

    if [ "$CERTMGR_PODS" -eq "$CERTMGR_TOTAL" ] && [ "$CERTMGR_PODS" -ge 3 ]; then
        echo -e "${GREEN}✓${NC} cert-manager: All $CERTMGR_PODS pods running"
    else
        echo -e "${YELLOW}⚠${NC} cert-manager: $CERTMGR_PODS/$CERTMGR_TOTAL pods running"
    fi
else
    echo -e "${YELLOW}⚠${NC} cert-manager namespace not found (not installed?)"
fi

# Check Monitoring
echo ""
echo -e "${BLUE}Checking Monitoring Stack...${NC}"
if kubectl get namespace monitoring &>/dev/null; then
    PROMETHEUS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    GRAFANA=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c "Running" || echo 0)

    if [ "$PROMETHEUS" -ge 1 ]; then
        echo -e "${GREEN}✓${NC} Prometheus: Running"
    else
        echo -e "${YELLOW}⚠${NC} Prometheus: Not running"
    fi

    if [ "$GRAFANA" -ge 1 ]; then
        echo -e "${GREEN}✓${NC} Grafana: Running"
    else
        echo -e "${YELLOW}⚠${NC} Grafana: Not running"
    fi
else
    echo -e "${YELLOW}⚠${NC} Monitoring namespace not found (not installed?)"
fi

# Check Harbor
echo ""
echo -e "${BLUE}Checking Harbor Registry...${NC}"
if kubectl get namespace harbor &>/dev/null; then
    HARBOR_CORE=$(kubectl get pods -n harbor -l component=core --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    HARBOR_REGISTRY=$(kubectl get pods -n harbor -l component=registry --no-headers 2>/dev/null | grep -c "Running" || echo 0)

    if [ "$HARBOR_CORE" -ge 1 ]; then
        echo -e "${GREEN}✓${NC} Harbor Core: Running"
    else
        echo -e "${YELLOW}⚠${NC} Harbor Core: Not running"
    fi

    if [ "$HARBOR_REGISTRY" -ge 1 ]; then
        echo -e "${GREEN}✓${NC} Harbor Registry: Running"
    else
        echo -e "${YELLOW}⚠${NC} Harbor Registry: Not running"
    fi
else
    echo -e "${YELLOW}⚠${NC} Harbor namespace not found (not installed?)"
fi

# Check for failed pods
echo ""
echo -e "${BLUE}Checking for failed pods...${NC}"
FAILED_PODS=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)

if [ "$FAILED_PODS" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No failed pods"
else
    echo -e "${YELLOW}⚠${NC} Found $FAILED_PODS pods not in Running/Succeeded state:"
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
fi

# Check cluster resource usage
echo ""
echo -e "${BLUE}Checking resource usage...${NC}"
if kubectl top nodes &>/dev/null; then
    echo -e "${GREEN}✓${NC} Node resource usage:"
    kubectl top nodes
else
    echo -e "${YELLOW}⚠${NC} Metrics server not available (kubectl top won't work)"
fi

# Summary
echo ""
echo "=========================================="
echo "Health Check Summary"
echo "=========================================="
echo ""

TOTAL_CHECKS=10
PASSED_CHECKS=$((
    (READY_NODES == NODE_COUNT ? 1 : 0) +
    (CILIUM_RUNNING >= 1 ? 1 : 0) +
    (METALLB_CONTROLLER >= 1 ? 1 : 0) +
    (INGRESS_PODS >= 1 ? 1 : 0) +
    (STORAGE_CLASS >= 1 ? 1 : 0) +
    (CERTMGR_PODS >= 3 ? 1 : 0) +
    (PROMETHEUS >= 1 ? 1 : 0) +
    (GRAFANA >= 1 ? 1 : 0) +
    (HARBOR_CORE >= 1 ? 1 : 0) +
    (FAILED_PODS == 0 ? 1 : 0)
))

if [ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]; then
    echo -e "${GREEN}✓ Cluster is healthy: $PASSED_CHECKS/$TOTAL_CHECKS checks passed${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Cluster has issues: $PASSED_CHECKS/$TOTAL_CHECKS checks passed${NC}"
    echo ""
    echo "Please review the output above for details."
    exit 1
fi
