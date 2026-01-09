# Single-Command Install Guide for EDA

## Quick Start

```bash
# 1. Install operator (creates eda-server-operator-system namespace)
kubectl apply -f https://github.com/ansible/eda-server-operator/releases/latest/download/operator.yaml

# 2. Deploy EDA instance (MUST be in eda-server-operator-system!)
kubectl apply -f eda-demo.yaml

# 3. Access EDA
kubectl port-forward svc/eda-ui -n eda 8081:80-server-operator-system
```

> **IMPORTANT:** The operator sets `WATCH_NAMESPACE` to its own namespace, so the EDA CR
> must be deployed to `eda-server-operator-system`, NOT a separate `eda` namespace!

---

## Key Differences from Kustomize Method

| Aspect | Single-Command | Kustomize Method |
|--------|---------------|------------------|
| Operator namespace | `eda-server-operator-system` | `eda` (configurable) |
| **EDA CR namespace** | **`eda-server-operator-system`** (required!) | `eda` (configurable) |
| Version control | Uses release tags | Can use `main` branch |
| Customization | Limited | Full control |
| Bug fixes | Waits for releases | Can use latest `main` |

---

## Known Issues with Release 1.0.2

The `latest` release (currently 1.0.2) has these bugs we encountered:

### 1. EDA UI Shows "Welcome to nginx!"
- **Cause:** nginx config points to `/usr/share/nginx/html` but UI files are in `/opt/app-root/ui/eda/`
- **Fix:** Add image overrides to use newer images:

```yaml
spec:
  image_web: quay.io/ansible/eda-ui
  image_web_version: "main"  # or "2.6.4"
```

### 2. No Default Organization
- **Cause:** Older eda-server doesn't auto-create organization
- **Fix:** Use newer server image:

```yaml
spec:
  image: quay.io/ansible/eda-server
  image_version: "main"
```

### 3. Activations Stuck in "Pending"
- **Cause:** dispatcherd/worker queue mismatch
- **Workaround:** Run ansible-rulebook manually in a pod (see demo below)

---

## Recommended eda-demo.yaml

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: eda
---
apiVersion: eda.ansible.com/v1alpha1
kind: EDA
metadata:
  name: eda
  namespace: eda
spec:
  automation_server_url: http://awx-service.awx.svc.cluster.local:80
  service_type: NodePort
  nodeport_port: 30081

  # USE THESE TO FIX BUGS in 1.0.2:
  image: quay.io/ansible/eda-server
  image_version: "main"
  image_web: quay.io/ansible/eda-ui
  image_web_version: "main"
```

---

## Complete Deployment Steps

### Step 1: Prerequisites
```bash
# Start minikube with enough resources
minikube start --cpus=4 --memory=12288 --addons=ingress

# Deploy AWX first (if not already done)
kubectl create namespace awx
kubectl apply -k ~/eda/awx-operator/
kubectl apply -f ~/eda/awx-operator/awx.yaml
```

### Step 2: Deploy EDA with Single Command
```bash
# Create namespace
kubectl create namespace eda

# Install operator
kubectl apply -f https://github.com/ansible/eda-server-operator/releases/latest/download/operator.yaml

# Wait for operator
kubectl wait --for=condition=Available deployment -l control-plane=controller-manager -n eda-server-operator-system --timeout=120s

# Deploy EDA instance (with bug fixes)
kubectl apply -f ~/eda/eda-demo.yaml

# Wait for EDA
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=eda-api -n eda --timeout=300s
```

### Step 3: Get Credentials
```bash
# EDA password
kubectl get secret eda-admin-password -n eda -o jsonpath='{.data.password}' | base64 -d

# AWX password
kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d
```

### Step 4: Access UIs
```bash
# Terminal 1
kubectl port-forward svc/awx-service -n awx 8080:80

# Terminal 2
kubectl port-forward svc/eda-ui -n eda 8081:80
```

---

## Running the Demo

Since activations may be stuck, run ansible-rulebook manually:

### Create AWX Token First
```bash
AWX_URL="http://127.0.0.1:XXXXX"  # Your AWX URL
AWX_PASS=$(kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d)

# Create token
curl -s -X POST "$AWX_URL/api/v2/tokens/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"description": "EDA Token", "scope": "write"}'
```

### Run Demo Pod
```bash
# Set your token
AWX_TOKEN="your-token-from-above"

# Create ConfigMap with rulebook
kubectl create configmap eda-demo-rulebook -n eda \
  --from-file=~/eda/demo-rulebook.yaml \
  --from-file=~/eda/demo-inventory.yaml

# Update demo-runner-pod.yaml with your token, then:
kubectl apply -f ~/eda/demo-runner-pod.yaml

# Watch it trigger AWX
kubectl logs -f eda-demo-runner -n eda
```

---

## Alternative: Use Main Branch Operator

If you want the latest fixes without waiting for a release:

```bash
# Instead of single-command install, use kustomize with main:
mkdir -p ~/eda/eda-operator

cat > ~/eda/eda-operator/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/eda-server-operator/config/default?ref=main
images:
  - name: quay.io/ansible/eda-server-operator
    newTag: main
namespace: eda
EOF

kubectl create namespace eda
kubectl apply -k ~/eda/eda-operator/
```

This gives you the latest bug fixes without needing image overrides.

---

## Troubleshooting

### Check Operator Status
```bash
kubectl get pods -n eda-server-operator-system
kubectl logs deployment/eda-server-operator-controller-manager -n eda-server-operator-system
```

### Check EDA Status
```bash
kubectl get eda -n eda
kubectl get pods -n eda
kubectl describe eda eda -n eda
```

### Reset EDA (Fresh Install)
```bash
kubectl delete eda eda -n eda
kubectl delete pvc -n eda --all
kubectl apply -f ~/eda/eda-demo.yaml
```
