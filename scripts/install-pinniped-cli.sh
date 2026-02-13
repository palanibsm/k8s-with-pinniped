#!/bin/bash
# Install Pinniped CLI for Kubernetes authentication

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VERSION="${PINNIPED_VERSION:-0.30.0}"
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

echo "=========================================="
echo "Pinniped CLI Installation"
echo "=========================================="
echo ""

# Map architecture
case $ARCH in
  x86_64)
    ARCH="amd64"
    ;;
  aarch64|arm64)
    ARCH="arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# Determine install location
if [ "$EUID" -eq 0 ]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="$HOME/.local/bin"
  mkdir -p "$INSTALL_DIR"
fi

echo "Installing Pinniped CLI v${VERSION} for ${OS}-${ARCH}..."
echo "Install directory: $INSTALL_DIR"
echo ""

# Download URL
DOWNLOAD_URL="https://get.pinniped.dev/v${VERSION}/pinniped-cli-${OS}-${ARCH}"

# Download binary
echo "Downloading from: $DOWNLOAD_URL"
if command -v curl &> /dev/null; then
  curl -fsSL "$DOWNLOAD_URL" -o /tmp/pinniped
elif command -v wget &> /dev/null; then
  wget -q "$DOWNLOAD_URL" -O /tmp/pinniped
else
  echo "Error: curl or wget is required"
  exit 1
fi

# Make executable
chmod +x /tmp/pinniped

# Move to install directory
mv /tmp/pinniped "$INSTALL_DIR/pinniped"

echo -e "${GREEN}✓${NC} Pinniped CLI installed successfully!"
echo ""

# Verify installation
if "$INSTALL_DIR/pinniped" version &>/dev/null; then
  echo "Pinniped version:"
  "$INSTALL_DIR/pinniped" version
else
  echo -e "${YELLOW}⚠${NC} Could not verify Pinniped installation"
fi

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""

# Add to PATH if not in system bin
if [ "$INSTALL_DIR" != "/usr/local/bin" ] && [ "$INSTALL_DIR" != "/usr/bin" ]; then
  if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo -e "${YELLOW}Note:${NC} $INSTALL_DIR is not in your PATH"
    echo ""
    echo "Add it to your shell profile:"
    echo "  echo 'export PATH=\$PATH:$INSTALL_DIR' >> ~/.bashrc"
    echo "  source ~/.bashrc"
    echo ""
  fi
fi

echo "Next steps:"
echo "1. Configure your kubeconfig: ./configure-pinniped-auth.sh"
echo "2. Test authentication: kubectl get nodes"
echo ""
