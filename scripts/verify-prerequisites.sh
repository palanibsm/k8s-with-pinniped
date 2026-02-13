#!/bin/bash
# Script to verify all prerequisites before installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Kubernetes Prerequisites Verification"
echo "=========================================="
echo ""

# Check if running as root or with sudo
if [ "$EUID" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Running with root privileges"
else
    echo -e "${RED}✗${NC} Please run with sudo or as root"
    exit 1
fi

# Check OS
echo ""
echo "Checking Operating System..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${GREEN}✓${NC} OS: $NAME $VERSION"

    if [[ "$ID" != "ubuntu" && "$ID" != "debian" && "$ID" != "rhel" && "$ID" != "centos" && "$ID" != "rocky" && "$ID" != "almalinux" ]]; then
        echo -e "${YELLOW}⚠${NC} Warning: Untested OS. Supported: Ubuntu, Debian, RHEL, CentOS, Rocky, AlmaLinux"
    fi
else
    echo -e "${RED}✗${NC} Cannot determine OS"
    exit 1
fi

# Check kernel version
echo ""
echo "Checking Kernel Version..."
KERNEL_VERSION=$(uname -r)
echo -e "${GREEN}✓${NC} Kernel: $KERNEL_VERSION"

# Check CPU cores
echo ""
echo "Checking CPU..."
CPU_CORES=$(nproc)
if [ "$CPU_CORES" -ge 2 ]; then
    echo -e "${GREEN}✓${NC} CPU Cores: $CPU_CORES (minimum 2 required)"
else
    echo -e "${RED}✗${NC} CPU Cores: $CPU_CORES (minimum 2 required)"
    exit 1
fi

# Check memory
echo ""
echo "Checking Memory..."
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_MEM" -ge 2 ]; then
    echo -e "${GREEN}✓${NC} Memory: ${TOTAL_MEM}GB (minimum 2GB required)"
else
    echo -e "${RED}✗${NC} Memory: ${TOTAL_MEM}GB (minimum 2GB required)"
    exit 1
fi

# Check disk space
echo ""
echo "Checking Disk Space..."
ROOT_DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$ROOT_DISK" -ge 20 ]; then
    echo -e "${GREEN}✓${NC} Root Disk Space: ${ROOT_DISK}GB available (minimum 20GB required)"
else
    echo -e "${YELLOW}⚠${NC} Root Disk Space: ${ROOT_DISK}GB available (recommended 20GB+)"
fi

# Check if swap is enabled
echo ""
echo "Checking Swap..."
if [ "$(swapon -s | wc -l)" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Swap is disabled (required for Kubernetes)"
else
    echo -e "${YELLOW}⚠${NC} Swap is enabled (will be disabled during installation)"
fi

# Check network connectivity
echo ""
echo "Checking Network Connectivity..."
if ping -c 1 8.8.8.8 &> /dev/null; then
    echo -e "${GREEN}✓${NC} Internet connectivity available"
else
    echo -e "${RED}✗${NC} No internet connectivity"
    exit 1
fi

# Check if required ports are not in use
echo ""
echo "Checking Required Ports..."

check_port() {
    local port=$1
    local description=$2
    if ! ss -tuln | grep -q ":$port "; then
        echo -e "${GREEN}✓${NC} Port $port is available ($description)"
    else
        echo -e "${YELLOW}⚠${NC} Port $port is in use ($description)"
    fi
}

# Control plane ports
check_port 6443 "Kubernetes API"
check_port 2379 "etcd client"
check_port 2380 "etcd peer"
check_port 10250 "kubelet"
check_port 10251 "kube-scheduler"
check_port 10252 "kube-controller-manager"

# Check if br_netfilter module can be loaded
echo ""
echo "Checking Kernel Modules..."
if modprobe br_netfilter 2>/dev/null; then
    echo -e "${GREEN}✓${NC} br_netfilter module can be loaded"
else
    echo -e "${RED}✗${NC} Cannot load br_netfilter module"
    exit 1
fi

if modprobe overlay 2>/dev/null; then
    echo -e "${GREEN}✓${NC} overlay module can be loaded"
else
    echo -e "${RED}✗${NC} Cannot load overlay module"
    exit 1
fi

# Check if IPv4 forwarding can be enabled
echo ""
echo "Checking sysctl Parameters..."
if [ -f /proc/sys/net/ipv4/ip_forward ]; then
    echo -e "${GREEN}✓${NC} IPv4 forwarding available"
else
    echo -e "${RED}✗${NC} IPv4 forwarding not available"
    exit 1
fi

# Check product_uuid
echo ""
echo "Checking Unique Identifiers..."
if [ -f /sys/class/dmi/id/product_uuid ]; then
    PRODUCT_UUID=$(cat /sys/class/dmi/id/product_uuid)
    echo -e "${GREEN}✓${NC} Product UUID: $PRODUCT_UUID"
else
    echo -e "${YELLOW}⚠${NC} Cannot read product_uuid"
fi

# Check hostname
echo ""
echo "Checking Hostname..."
HOSTNAME=$(hostname)
if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "localhost" ]; then
    echo -e "${GREEN}✓${NC} Hostname: $HOSTNAME"
else
    echo -e "${YELLOW}⚠${NC} Hostname should be set to something other than localhost"
fi

# Check if SELinux is present (RHEL/CentOS)
if [ -f /etc/selinux/config ]; then
    echo ""
    echo "Checking SELinux..."
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Not present")
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        echo -e "${YELLOW}⚠${NC} SELinux is Enforcing (will be set to Permissive during installation)"
    else
        echo -e "${GREEN}✓${NC} SELinux: $SELINUX_STATUS"
    fi
fi

# Check time synchronization
echo ""
echo "Checking Time Synchronization..."
if systemctl is-active --quiet chronyd || systemctl is-active --quiet systemd-timesyncd; then
    echo -e "${GREEN}✓${NC} Time synchronization is active"
else
    echo -e "${YELLOW}⚠${NC} Time synchronization not active (will be configured during installation)"
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Complete!"
echo "=========================================="
echo ""
echo -e "${GREEN}System is ready for Kubernetes installation${NC}"
echo ""
echo "Next steps:"
echo "1. Update ansible/inventory/hosts.yml with your node IPs"
echo "2. Update ansible/inventory/group_vars/all.yml with your configuration"
echo "3. Run: cd ansible && ansible-playbook -i inventory/hosts.yml playbooks/01-prerequisites.yml"
echo ""
