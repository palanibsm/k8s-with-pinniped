# Azure AD Configuration for Pinniped

Complete guide to configure Azure AD (Entra ID) for Kubernetes authentication via Pinniped.

## Prerequisites

- Azure AD (Entra ID) tenant
- Permissions to create App Registrations and Groups
- Access to Azure Portal (https://portal.azure.com)

## Step 1: Create Azure AD Groups

### 1.1 Navigate to Azure AD Groups

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** → **Groups**
3. Click **+ New group**

### 1.2 Create Required Groups

Create the following 4 groups:

#### Group 1: k8s-cluster-admins
```
Group type: Security
Group name: k8s-cluster-admins
Group description: Kubernetes Cluster Administrators - Full cluster access
Membership type: Assigned
```
**Add members**: Add users who should have full cluster admin access

#### Group 2: k8s-developers
```
Group type: Security
Group name: k8s-developers
Group description: Kubernetes Developers - Can manage applications in dev/staging
Membership type: Assigned
```
**Add members**: Add developer users

#### Group 3: k8s-viewers
```
Group type: Security
Group name: k8s-viewers
Group description: Kubernetes Viewers - Read-only access to cluster resources
Membership type: Assigned
```
**Add members**: Add users who need read-only access

#### Group 4: k8s-namespace-owners
```
Group type: Security
Group name: k8s-namespace-owners
Group description: Kubernetes Namespace Owners - Full control within specific namespaces
Membership type: Assigned
```
**Add members**: Add team leads or namespace administrators

### 1.3 Record Group Object IDs

For each group created:
1. Click on the group name
2. Copy the **Object ID** (UUID format)
3. Save these IDs - you'll need them later

**Example:**
```
k8s-cluster-admins: 12345678-1234-1234-1234-123456789abc
k8s-developers: 87654321-4321-4321-4321-cba987654321
k8s-viewers: 11111111-2222-3333-4444-555555555555
k8s-namespace-owners: 99999999-8888-7777-6666-444444444444
```

## Step 2: Create App Registration

### 2.1 Register New Application

1. In Azure Portal, go to **Azure Active Directory** → **App registrations**
2. Click **+ New registration**
3. Fill in the details:

```
Name: kubernetes-pinniped-auth
Supported account types: Accounts in this organizational directory only (Single tenant)
Redirect URI:
  Platform: Web
  URL: https://pinniped.emergingtechnation.com/callback
```

4. Click **Register**

### 2.2 Record Application IDs

After registration, you'll see:
- **Application (client) ID**: Copy this (e.g., `abcd1234-5678-90ab-cdef-1234567890ab`)
- **Directory (tenant) ID**: Copy this (e.g., `tenant12-3456-7890-abcd-ef1234567890`)

### 2.3 Create Client Secret

1. In your app registration, go to **Certificates & secrets**
2. Click **+ New client secret**
3. Add description: `kubernetes-pinniped-secret`
4. Set expiration: **24 months** (or as per your policy)
5. Click **Add**
6. **IMPORTANT**: Copy the secret **Value** immediately (you won't see it again)
   - Example: `AbC123dEf456~GhI789jKl012-MnO345pQr678`

### 2.4 Configure API Permissions

1. Go to **API permissions**
2. Click **+ Add a permission**
3. Select **Microsoft Graph**
4. Select **Delegated permissions**
5. Add these permissions:
   - `User.Read` - Read user profile
   - `GroupMember.Read.All` - Read group memberships
   - `openid` - OpenID Connect sign-in
   - `profile` - View users' basic profile
   - `email` - View users' email address

6. Click **Add permissions**
7. Click **Grant admin consent for [Your Organization]**
8. Confirm by clicking **Yes**

### 2.5 Configure Authentication

1. Go to **Authentication**
2. Under **Redirect URIs**, verify:
   ```
   https://pinniped.emergingtechnation.com/callback
   ```

3. Under **Implicit grant and hybrid flows**, enable:
   - ✅ ID tokens (used for implicit and hybrid flows)

4. Under **Advanced settings**:
   - Allow public client flows: **No**
   - Enable the following mobile and desktop flows: **No**

5. Click **Save**

### 2.6 Configure Token Configuration (Optional but Recommended)

1. Go to **Token configuration**
2. Click **+ Add groups claim**
3. Select:
   - ✅ Security groups
4. For ID token, select: **Group ID**
5. Click **Add**

## Step 3: Configure Redirect URIs (After Pinniped Installation)

After deploying Pinniped Supervisor, you may need to add additional redirect URIs:

1. Go back to **App registrations** → **kubernetes-pinniped-auth** → **Authentication**
2. Add these additional redirect URIs:
   ```
   https://pinniped.emergingtechnation.com/callback
   http://localhost:12345/callback  (for local kubectl authentication)
   http://127.0.0.1:12345/callback  (for local kubectl authentication)
   ```

## Step 4: Prepare Configuration Values

Create a secure file with your Azure AD configuration. **DO NOT commit this to Git!**

Create file: `ansible/inventory/group_vars/azure_ad_secrets.yml`

```yaml
---
# Azure AD Configuration for Pinniped
# KEEP THIS FILE SECURE - DO NOT COMMIT TO GIT

# Azure AD Tenant Information
azure_tenant_id: "tenant12-3456-7890-abcd-ef1234567890"  # Your Directory (tenant) ID

# Azure AD Application Information
azure_client_id: "abcd1234-5678-90ab-cdef-1234567890ab"  # Your Application (client) ID
azure_client_secret: "AbC123dEf456~GhI789jKl012-MnO345pQr678"  # Your client secret VALUE

# Azure AD Group Object IDs (from Step 1.3)
azure_ad_group_ids:
  cluster_admins: "12345678-1234-1234-1234-123456789abc"  # k8s-cluster-admins
  developers: "87654321-4321-4321-4321-cba987654321"      # k8s-developers
  viewers: "11111111-2222-3333-4444-555555555555"         # k8s-viewers
  namespace_owners: "99999999-8888-7777-6666-444444444444" # k8s-namespace-owners
```

## Step 5: Encrypt Secrets with Ansible Vault

```bash
cd ansible

# Create vault password file (keep this secure!)
echo "your-strong-vault-password" > .vault-password

# Add to .gitignore (already included)
echo ".vault-password" >> ../.gitignore

# Encrypt the secrets file
ansible-vault encrypt inventory/group_vars/azure_ad_secrets.yml \
  --vault-password-file .vault-password

# Verify encryption
cat inventory/group_vars/azure_ad_secrets.yml
# Should show encrypted content
```

## Step 6: Update Variables

Edit `ansible/inventory/group_vars/all.yml` and add:

```yaml
# Pinniped Configuration
pinniped_enabled: true
pinniped_supervisor_version: "0.30.0"
pinniped_concierge_version: "0.30.0"
pinniped_supervisor_domain: "pinniped.emergingtechnation.com"

# Azure AD Issuer URL
azure_ad_issuer_url: "https://login.microsoftonline.com/{{ azure_tenant_id }}/v2.0"
```

## Verification Checklist

Before proceeding with Pinniped installation, verify:

- ✅ 4 Azure AD groups created
- ✅ Group Object IDs recorded
- ✅ App registration created
- ✅ Client ID and Tenant ID recorded
- ✅ Client secret created and saved
- ✅ API permissions granted (with admin consent)
- ✅ Redirect URIs configured
- ✅ Configuration file created and encrypted with Ansible Vault
- ✅ Variables updated in all.yml

## Security Best Practices

### Client Secret Rotation

Azure AD client secrets have an expiration date. Set up a reminder to rotate before expiration:

```bash
# Check secret expiration in Azure Portal
# App registrations → kubernetes-pinniped-auth → Certificates & secrets

# To rotate:
# 1. Create new secret
# 2. Update ansible/inventory/group_vars/azure_ad_secrets.yml
# 3. Re-encrypt with ansible-vault
# 4. Run playbook: ansible-playbook playbooks/15-pinniped-supervisor.yml
# 5. Test authentication
# 6. Delete old secret in Azure Portal
```

### Vault Password Management

**IMPORTANT**: Keep `.vault-password` file secure!

```bash
# Secure the vault password file
chmod 600 ansible/.vault-password

# Alternative: Use environment variable
export ANSIBLE_VAULT_PASSWORD_FILE=.vault-password
```

## Troubleshooting

### Cannot Grant Admin Consent

**Error**: "Need admin approval" when granting permissions

**Solution**: You need Azure AD admin rights. Contact your Azure AD administrator.

### Group Claims Not Appearing

**Issue**: User authenticated but no group membership in token

**Solutions**:
1. Verify user is member of Azure AD groups
2. Check Token Configuration includes groups claim
3. Verify API permission `GroupMember.Read.All` is granted
4. Wait 5-10 minutes after granting permissions (Azure AD propagation)

### Redirect URI Mismatch

**Error**: "AADSTS50011: The reply URL does not match"

**Solution**:
1. Check exact match of redirect URI in Azure AD
2. Include both `https://pinniped.emergingtechnation.com/callback` and localhost URIs
3. No trailing slashes

## Next Steps

Once Azure AD is configured:
1. Run Pinniped Supervisor installation: `ansible-playbook playbooks/15-pinniped-supervisor.yml`
2. Run Pinniped Concierge installation: `ansible-playbook playbooks/16-pinniped-concierge.yml`
3. Configure RBAC: `ansible-playbook playbooks/17-pinniped-rbac.yml`
4. Test authentication with a user

## Additional Resources

- [Azure AD App Registrations Documentation](https://learn.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)
- [Pinniped Documentation](https://pinniped.dev)
- [OIDC with Azure AD](https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-protocols-oidc)
