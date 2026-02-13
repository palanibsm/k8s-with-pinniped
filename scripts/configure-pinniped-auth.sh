#!/bin/bash
# Configure kubectl to use Pinniped authentication with Azure AD

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Configure Kubectl with Pinniped"
echo "=========================================="
echo ""

# Check if pinniped CLI is installed
if ! command -v pinniped &> /dev/null; then
  echo -e "${YELLOW}⚠${NC} Pinniped CLI not found!"
  echo ""
  echo "Please install it first:"
  echo "  ./install-pinniped-cli.sh"
  exit 1
fi

# Check if kubeconfig template exists
TEMPLATE_FILE="../configs/pinniped/kubeconfig-template.yaml"
if [ ! -f "$TEMPLATE_FILE" ]; then
  echo -e "${YELLOW}⚠${NC} Kubeconfig template not found at: $TEMPLATE_FILE"
  echo ""
  echo "Please run the Pinniped installation playbooks first:"
  echo "  ansible-playbook playbooks/15-pinniped-supervisor.yml"
  echo "  ansible-playbook playbooks/16-pinniped-concierge.yml"
  exit 1
fi

# Get cluster info
echo -e "${BLUE}Cluster Information:${NC}"
CLUSTER_NAME=$(grep "name: kubernetes-cluster" "$TEMPLATE_FILE" | head -1 | awk '{print $3}')
echo "  Cluster: $CLUSTER_NAME"

PINNIPED_DOMAIN=$(grep "issuer=" "$TEMPLATE_FILE" | sed 's/.*issuer=https:\/\///' | sed 's/--//')
echo "  Pinniped Domain: $PINNIPED_DOMAIN"

echo ""

# Ask for confirmation
read -p "Configure kubectl to use Pinniped authentication? (y/n): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Configuration cancelled."
  exit 0
fi

# Backup existing kubeconfig
if [ -f "$HOME/.kube/config" ]; then
  echo "Backing up existing kubeconfig..."
  cp "$HOME/.kube/config" "$HOME/.kube/config.backup.$(date +%Y%m%d-%H%M%S)"
  echo -e "${GREEN}✓${NC} Backup created"
fi

# Copy template to user's kubeconfig
mkdir -p "$HOME/.kube"
cp "$TEMPLATE_FILE" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

echo -e "${GREEN}✓${NC} Kubeconfig configured with Pinniped authentication"
echo ""

# Test configuration
echo "Testing configuration..."
echo ""

if kubectl cluster-info &>/dev/null; then
  echo -e "${GREEN}✓${NC} Cluster is reachable"
else
  echo -e "${YELLOW}⚠${NC} Cannot reach cluster (may need to authenticate first)"
fi

echo ""
echo "=========================================="
echo "Configuration Complete!"
echo "=========================================="
echo ""
echo "To authenticate and access the cluster:"
echo "  kubectl get nodes"
echo ""
echo "This will open a browser window for Azure AD authentication."
echo ""
echo "Your Azure AD group membership will determine your permissions:"
echo "  - k8s-cluster-admins: Full cluster access"
echo "  - k8s-developers: Application management"
echo "  - k8s-viewers: Read-only access"
echo "  - k8s-namespace-owners: Namespace-specific admin"
echo ""
echo "If you have issues, check:"
echo "  1. DNS resolves: nslookup $PINNIPED_DOMAIN"
echo "  2. Pinniped is accessible: curl https://$PINNIPED_DOMAIN/.well-known/openid-configuration"
echo "  3. You're a member of at least one Azure AD group"
echo ""
