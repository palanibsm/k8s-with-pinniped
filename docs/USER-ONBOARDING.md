# Kubernetes Cluster Access - User Onboarding Guide

Welcome! This guide will help you set up access to the Kubernetes cluster using Azure AD authentication.

## Prerequisites

- Azure AD account with membership in at least one Kubernetes group:
  - `k8s-cluster-admins` - Full admin access
  - `k8s-developers` - Application management
  - `k8s-viewers` - Read-only access
  - `k8s-namespace-owners` - Namespace admin
- kubectl installed on your machine
- Internet access

## Step 1: Install kubectl (if not installed)

### Linux / WSL
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

### macOS
```bash
brew install kubectl
```

### Windows (PowerShell as Admin)
```powershell
choco install kubernetes-cli
```

Verify installation:
```bash
kubectl version --client
```

## Step 2: Install Pinniped CLI

Pinniped CLI handles the authentication with Azure AD.

### Option A: Automated Script (Recommended)

```bash
# Download and run installation script
curl -fsSL https://your-repo/scripts/install-pinniped-cli.sh | bash

# Or if you have the repo cloned
cd k8s-repo
./scripts/install-pinniped-cli.sh
```

### Option B: Manual Installation

**Linux/WSL:**
```bash
VERSION="0.30.0"
curl -fsSL "https://get.pinniped.dev/v${VERSION}/pinniped-cli-linux-amd64" -o pinniped
chmod +x pinniped
sudo mv pinniped /usr/local/bin/
```

**macOS:**
```bash
VERSION="0.30.0"
curl -fsSL "https://get.pinniped.dev/v${VERSION}/pinniped-cli-darwin-amd64" -o pinniped
chmod +x pinniped
sudo mv pinniped /usr/local/bin/
```

**Windows:**
```powershell
$VERSION = "0.30.0"
Invoke-WebRequest -Uri "https://get.pinniped.dev/v${VERSION}/pinniped-cli-windows-amd64.exe" -OutFile "pinniped.exe"
Move-Item -Path "pinniped.exe" -Destination "C:\Windows\System32\pinniped.exe"
```

Verify installation:
```bash
pinniped version
```

## Step 3: Configure kubectl

### Option A: Automated Configuration (Recommended)

```bash
# Download and run configuration script
./scripts/configure-pinniped-auth.sh
```

### Option B: Manual Configuration

1. Request kubeconfig from your cluster administrator
2. Save it to `~/.kube/config`
3. Set permissions:
   ```bash
   chmod 600 ~/.kube/config
   ```

Example kubeconfig content:
```yaml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: <CLUSTER_CA>
    server: https://<CLUSTER_API>:6443
  name: kubernetes-cluster
contexts:
- context:
    cluster: kubernetes-cluster
    user: pinniped-user
  name: pinniped-context
current-context: pinniped-context
users:
- name: pinniped-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: pinniped
      args:
      - login
      - oidc
      - --issuer=https://pinniped.emergingtechnation.com
      - --client-id=kubernetes
      - --scopes=openid,email,profile,groups,offline_access
      - --request-audience=kubernetes
```

## Step 4: Authenticate and Test Access

### First Authentication

Run any kubectl command to trigger authentication:

```bash
kubectl get nodes
```

**What happens:**
1. Pinniped CLI opens your default browser
2. You're redirected to Azure AD login
3. Enter your Azure AD credentials (email + password)
4. Complete MFA if enabled
5. Grant permissions when prompted
6. Browser shows "You have been logged in" message
7. kubectl command completes

### Test Your Access Level

```bash
# View nodes (all users should have this)
kubectl get nodes

# View pods in all namespaces (admins and viewers)
kubectl get pods -A

# Create a test deployment (admins and developers)
kubectl create deployment nginx --image=nginx -n default

# Delete the test deployment (admins and developers)
kubectl delete deployment nginx -n default

# View logs (admins, developers, and viewers)
kubectl logs <pod-name>
```

## Access Levels

Your permissions depend on your Azure AD group membership:

### 🔴 Cluster Admins (k8s-cluster-admins)
- Full cluster access
- Can create/delete namespaces
- Can modify RBAC
- Can access all resources cluster-wide

**Example commands:**
```bash
kubectl get nodes
kubectl create namespace test
kubectl delete namespace test
kubectl get pods -n kube-system
```

### 🟢 Developers (k8s-developers)
- Can manage applications (deployments, services, ingress)
- Can create ConfigMaps and Secrets
- Can view nodes (read-only)
- Cannot delete namespaces or modify RBAC

**Example commands:**
```bash
kubectl create deployment myapp --image=nginx
kubectl expose deployment myapp --port=80
kubectl scale deployment myapp --replicas=3
kubectl logs deployment/myapp
```

### 🔵 Viewers (k8s-viewers)
- Read-only access to resources
- Can view pods, deployments, services
- Cannot create, modify, or delete resources

**Example commands:**
```bash
kubectl get pods
kubectl get deployments
kubectl logs <pod-name>
kubectl describe pod <pod-name>
```

### 🟡 Namespace Owners (k8s-namespace-owners)
- Full control within assigned namespaces (dev, staging)
- Cannot access other namespaces
- Cannot delete namespaces or modify RBAC

**Example commands:**
```bash
kubectl get pods -n dev
kubectl create deployment myapp --image=nginx -n dev
kubectl delete deployment myapp -n dev
```

## Common Tasks

### View Your Current Context
```bash
kubectl config current-context
```

### List Available Contexts
```bash
kubectl config get-contexts
```

### Switch Context (if you have multiple)
```bash
kubectl config use-context pinniped-context
```

### Check Your Permissions
```bash
# List all permissions you have
kubectl auth can-i --list

# Check specific permission
kubectl auth can-i create deployments
kubectl auth can-i delete namespaces
```

### View Cluster Resources
```bash
# Nodes
kubectl get nodes

# Pods in current namespace
kubectl get pods

# Pods in all namespaces
kubectl get pods -A

# Services
kubectl get services

# Ingresses
kubectl get ingress
```

## Troubleshooting

### Authentication Issues

**Issue**: Browser doesn't open
- **Solution**: Check firewall settings, try different browser
- Manual URL: Check terminal output for login URL

**Issue**: "Authentication failed"
- **Solution**: Verify you're using correct Azure AD credentials
- Check with admin that you're member of a Kubernetes group

**Issue**: "Permission denied"
- **Solution**: Contact admin to verify your group membership
- Run: `kubectl auth can-i --list` to see your permissions

### Connection Issues

**Issue**: "Unable to connect to the server"
- **Solution**: Check VPN connection (if required)
- Verify DNS: `nslookup pinniped.emergingtechnation.com`
- Check firewall rules

**Issue**: "x509: certificate signed by unknown authority"
- **Solution**: Update CA certificates on your system
- For testing only: `kubectl --insecure-skip-tls-verify get nodes`

### Token Expiration

Tokens are automatically refreshed. If you see authentication errors:

```bash
# Force re-authentication
kubectl get nodes --v=6

# Clear cached credentials (if needed)
rm -rf ~/.config/pinniped
```

## Security Best Practices

### ✅ Do's
- Use kubectl from secure, trusted machines
- Keep kubectl and Pinniped CLI updated
- Log out of shared computers: Clear `~/.config/pinniped`
- Report suspicious activity immediately
- Use MFA on your Azure AD account

### ❌ Don'ts
- Don't share your kubeconfig file
- Don't disable certificate verification
- Don't use the same kubeconfig on untrusted machines
- Don't commit kubeconfig to Git repositories
- Don't bypass authentication prompts

## Getting Help

### Check Cluster Status
```bash
kubectl cluster-info
kubectl get componentstatuses
```

### View Recent Events
```bash
kubectl get events --sort-by='.lastTimestamp'
```

### Contact Support

**For access issues:**
- Contact: cluster-admin@yourcompany.com
- Include: Your Azure AD email and error message

**For technical issues:**
- Kubernetes Dashboard: https://dashboard.k8s.example.com
- Grafana Monitoring: https://grafana.emergingtechnation.com
- Documentation: https://github.com/your-org/k8s-repo

## Useful kubectl Commands Cheat Sheet

```bash
# Get resources
kubectl get pods
kubectl get deployments
kubectl get services
kubectl get ingress

# Describe resource
kubectl describe pod <pod-name>
kubectl describe deployment <deployment-name>

# View logs
kubectl logs <pod-name>
kubectl logs <pod-name> -f  # Follow logs
kubectl logs <pod-name> --previous  # Previous container

# Execute commands in pod
kubectl exec -it <pod-name> -- /bin/bash
kubectl exec <pod-name> -- ls /app

# Create resources
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80

# Delete resources
kubectl delete pod <pod-name>
kubectl delete deployment <deployment-name>

# Scale deployment
kubectl scale deployment <deployment-name> --replicas=3

# View resource usage
kubectl top nodes
kubectl top pods
```

## Next Steps

1. **Explore the cluster**: Try `kubectl get pods -A`
2. **Deploy your first app**: See deployment guides
3. **Set up CI/CD**: Integrate with your pipelines
4. **Learn more**: [Kubernetes Documentation](https://kubernetes.io/docs/)

---

**Welcome to the cluster! 🚀**

If you have questions, check with your team's Kubernetes administrator or refer to the troubleshooting section above.
