# Step-by-Step Guide: Deploy AWX and EDA on Minikube

## Prerequisites
- Docker Desktop with 12GB+ memory allocated
- minikube installed
- kubectl installed

---

## Step 1: Start Minikube

```bash
# Delete existing minikube (if any)
minikube delete

# Start fresh with adequate resources
minikube start --cpus=4 --memory=12288 --addons=ingress

# Verify it's running
minikube status
```

---

## Step 2: Deploy AWX

```bash
# Create namespace
kubectl create namespace awx

# Create operator kustomization directory
mkdir -p ~/eda/awx-operator

# Create kustomization.yaml
cat > ~/eda/awx-operator/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=2.19.1
images:
  - name: quay.io/ansible/awx-operator
    newTag: 2.19.1
namespace: awx
EOF

# Deploy AWX operator
kubectl apply -k ~/eda/awx-operator/

# Wait for operator to be ready
kubectl wait --for=condition=Available deployment/awx-operator-controller-manager -n awx --timeout=120s

# Create AWX instance
cat > ~/eda/awx-operator/awx.yaml << 'EOF'
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: awx
spec:
  service_type: NodePort
  nodeport_port: 30080
EOF

kubectl apply -f ~/eda/awx-operator/awx.yaml

# Wait for AWX to be ready (this takes 3-5 minutes)
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=awx-web -n awx --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=awx-task -n awx --timeout=300s

# Get AWX admin password
echo "AWX Password: $(kubectl get secret awx-demo-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d)"
```

---

## Step 3: Deploy EDA

**IMPORTANT:** Use `main` branch of the operator to avoid UI and organization issues.

```bash
# Create namespace
kubectl create namespace eda

# Create operator kustomization directory
mkdir -p ~/eda/eda-operator

# Create kustomization.yaml (use main branch!)
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

# Deploy EDA operator
kubectl apply -k ~/eda/eda-operator/

# Wait for operator to be ready
kubectl wait --for=condition=Available deployment/eda-server-operator-controller-manager -n eda --timeout=120s

# Create EDA instance
cat > ~/eda/eda-operator/eda.yaml << 'EOF'
apiVersion: eda.ansible.com/v1alpha1
kind: EDA
metadata:
  name: eda
  namespace: eda
spec:
  automation_server_url: http://awx-demo-service.awx.svc.cluster.local:80
  service_type: NodePort
  nodeport_port: 30081
EOF

kubectl apply -f ~/eda/eda-operator/eda.yaml

# Wait for EDA to be ready (this takes 2-3 minutes)
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=eda-api -n eda --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=eda-ui -n eda --timeout=300s

# Get EDA admin password
echo "EDA Password: $(kubectl get secret eda-admin-password -n eda -o jsonpath='{.data.password}' | base64 -d)"
```

---

## Step 4: Access the UIs

Run these in **separate terminals** (they need to stay open):

```bash
# Terminal 1 - AWX
kubectl port-forward svc/awx-demo-service -n awx 8080:80

# Terminal 2 - EDA
kubectl port-forward svc/eda-ui -n eda 8081:80
```

Note the URLs that are printed (e.g., http://127.0.0.1:XXXXX)

---

## Step 5: Set Up AWX Demo Resources

```bash
# Set your AWX URL (from step 4)
AWX_URL="http://127.0.0.1:XXXXX"  # Replace with actual URL
AWX_PASS=$(kubectl get secret awx-demo-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d)

# Create Project
curl -s -X POST "$AWX_URL/api/v2/projects/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"name": "Demo Project", "scm_type": "git", "scm_url": "https://github.com/ansible/ansible-tower-samples", "organization": 1}'

# Wait for project sync
sleep 30

# Create Inventory
curl -s -X POST "$AWX_URL/api/v2/inventories/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"name": "Demo Inventory", "organization": 1}'

# Add localhost to inventory
curl -s -X POST "$AWX_URL/api/v2/inventories/1/hosts/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"name": "localhost", "variables": "ansible_connection: local"}'

# Create Job Template
curl -s -X POST "$AWX_URL/api/v2/job_templates/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"name": "Demo Job Template", "job_type": "run", "inventory": 1, "project": 6, "playbook": "hello_world.yml"}'

# Create Token for EDA
curl -s -X POST "$AWX_URL/api/v2/tokens/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"description": "EDA Token", "scope": "write"}'

# Note the token value from the output!
```

---

## Step 6: Trigger AWX Job from EDA

```bash
# Get the token from Step 5 output
AWX_TOKEN="your-token-here"

# Create demo files
mkdir -p ~/eda

# Create rulebook
cat > ~/eda/demo-rulebook.yaml << 'EOF'
---
- name: Trigger AWX Demo
  hosts: all
  sources:
    - ansible.eda.range:
        limit: 3
  rules:
    - name: Trigger AWX Job on event
      condition: event.i == 1
      action:
        run_job_template:
          name: Demo Job Template
          organization: Default
EOF

# Create inventory
cat > ~/eda/demo-inventory.yaml << 'EOF'
all:
  hosts:
    localhost:
      ansible_connection: local
EOF

# Create ConfigMap
kubectl delete configmap eda-demo-rulebook -n eda --ignore-not-found=true
kubectl create configmap eda-demo-rulebook -n eda \
  --from-file=~/eda/demo-rulebook.yaml \
  --from-file=~/eda/demo-inventory.yaml

# Create runner pod (update YOUR_TOKEN)
cat > ~/eda/demo-runner-pod.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: eda-demo-runner
  namespace: eda
spec:
  restartPolicy: Never
  containers:
  - name: ansible-rulebook
    image: quay.io/ansible/ansible-rulebook:v1.1.1
    env:
    - name: EDA_CONTROLLER_URL
      value: "http://awx-demo-service.awx.svc.cluster.local"
    - name: EDA_CONTROLLER_TOKEN
      value: "$AWX_TOKEN"
    - name: EDA_CONTROLLER_SSL_VERIFY
      value: "no"
    command:
    - ansible-rulebook
    args:
    - --rulebook
    - /rulebooks/demo-rulebook.yaml
    - --inventory
    - /rulebooks/demo-inventory.yaml
    - -vv
    volumeMounts:
    - name: rulebook-volume
      mountPath: /rulebooks
  volumes:
  - name: rulebook-volume
    configMap:
      name: eda-demo-rulebook
EOF

# Run the demo
kubectl delete pod eda-demo-runner -n eda --ignore-not-found=true
kubectl apply -f ~/eda/demo-runner-pod.yaml

# Watch the logs
kubectl logs -f eda-demo-runner -n eda

# Check AWX for the triggered job
curl -s "$AWX_URL/api/v2/jobs/" -u "admin:$AWX_PASS" | jq '.results[] | {id, name, status}'
```

---

## Verification

You should see:
1. EDA rulebook receives events (i=0, i=1, i=2)
2. Event i=1 matches the condition
3. Action `run_job_template` is triggered
4. AWX job "Demo Job Template" runs and completes successfully

---

## Cleanup

```bash
# Delete everything
minikube delete
rm -rf ~/eda
```

---

## Known Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| EDA UI shows nginx welcome | Old operator/image | Use operator `main` branch |
| No Default organization | Old operator | Use operator `main` branch |
| Migration errors on upgrade | Incompatible DB schema | Delete PVCs before redeploying |
| Activations stuck pending | dispatcherd bug in main | Run ansible-rulebook manually in pod |

---

## File Structure

```
~/eda/
├── awx-operator/
│   ├── kustomization.yaml
│   └── awx.yaml
├── eda-operator/
│   ├── kustomization.yaml
│   └── eda.yaml
├── demo-rulebook.yaml
├── demo-inventory.yaml
└── demo-runner-pod.yaml
```
