# Quick Start: AWX + EDA on Minikube (Single Command Method)

## Step 1: Start Minikube

```bash
minikube delete
minikube start --cpus=4 --memory=12288 --addons=ingress
```

## Step 2: Deploy AWX

```bash
# Install AWX operator
kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/2.19.1/deploy/awx-operator.yaml

# Wait for operator
kubectl wait --for=condition=Available deployment/awx-operator-controller-manager -n awx --timeout=120s

# Deploy AWX instance
cat <<EOF | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: awx
spec:
  service_type: NodePort
  nodeport_port: 30080
EOF

# Wait for AWX (takes 3-5 minutes)
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=awx-web -n awx --timeout=300s
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=awx-task -n awx --timeout=300s

# Get AWX password
echo "AWX Password: $(kubectl get secret awx-demo-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d)"
```

## Step 3: Deploy EDA

```bash
# Install EDA operator
kubectl apply -f https://github.com/ansible/eda-server-operator/releases/latest/download/operator.yaml

# Wait for operator
kubectl wait --for=condition=Available deployment/eda-server-operator-controller-manager -n eda-server-operator-system --timeout=120s

# Deploy EDA instance
cat <<EOF | kubectl apply -f -
apiVersion: eda.ansible.com/v1alpha1
kind: EDA
metadata:
  name: eda
  namespace: eda-server-operator-system
spec:
  automation_server_url: http://awx-demo-service.awx.svc.cluster.local:80
  service_type: NodePort
  nodeport_port: 30081
  image: quay.io/ansible/eda-server
  image_version: "sha-ad278f8"
  image_web: quay.io/ansible/eda-ui
  image_web_version: "2.6.4"
  postgres_image: quay.io/sclorg/postgresql-15-c9s
  postgres_image_version: "latest"
EOF

# Wait for EDA (takes 2-3 minutes)
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=eda-api -n eda-server-operator-system --timeout=300s

# Get EDA password
echo "EDA Password: $(kubectl get secret eda-admin-password -n eda-server-operator-system -o jsonpath='{.data.password}' | base64 -d)"
```

## Step 4: Access UIs

Run in **separate terminals**:

```bash
# Terminal 1 - AWX
kubectl port-forward svc/awx-demo-service -n awx 8080:80

# Terminal 2 - EDA
kubectl port-forward svc/eda-ui -n eda 8081:80-server-operator-system
```

## Step 5: Setup AWX Resources

```bash
# Set variables (update AWX_URL from Terminal 1 output)
AWX_URL="http://127.0.0.1:XXXXX"
AWX_PASS=$(kubectl get secret awx-demo-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d)

# Create Project
curl -s -X POST "$AWX_URL/api/v2/projects/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"name":"Demo Project","scm_type":"git","scm_url":"https://github.com/ansible/ansible-tower-samples","organization":1}'

# Wait for sync
sleep 30

# Create Inventory
curl -s -X POST "$AWX_URL/api/v2/inventories/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"name":"Demo Inventory","organization":1}'

# Add Host
curl -s -X POST "$AWX_URL/api/v2/inventories/1/hosts/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"name":"localhost","variables":"ansible_connection: local"}'

# Create Job Template
curl -s -X POST "$AWX_URL/api/v2/job_templates/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"name":"Demo Job Template","job_type":"run","inventory":1,"project":6,"playbook":"hello_world.yml"}'

# Create Token for EDA
AWX_TOKEN=$(curl -s -X POST "$AWX_URL/api/v2/tokens/" \
  -H "Content-Type: application/json" \
  -u "admin:$AWX_PASS" \
  -d '{"description":"EDA Token","scope":"write"}' | grep -o '"token":"[^"]*' | cut -d'"' -f4)

echo "AWX Token: $AWX_TOKEN"
```

## Step 6: Run EDA Demo

```bash
# Create demo rulebook
cat <<'EOF' > /tmp/demo-rulebook.yaml
---
- name: Trigger AWX Demo
  hosts: all
  sources:
    - ansible.eda.range:
        limit: 3
  rules:
    - name: Trigger AWX Job
      condition: event.i == 1
      action:
        run_job_template:
          name: Demo Job Template
          organization: Default
EOF

# Create inventory
cat <<'EOF' > /tmp/demo-inventory.yaml
all:
  hosts:
    localhost:
      ansible_connection: local
EOF

# Create ConfigMap
kubectl create configmap eda-demo-rulebook -n eda-server-operator-system \
  --from-file=/tmp/demo-rulebook.yaml \
  --from-file=/tmp/demo-inventory.yaml

# Run demo (replace YOUR_TOKEN with AWX_TOKEN from Step 5)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: eda-demo-runner
  namespace: eda-server-operator-system
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
    command: ["ansible-rulebook"]
    args: ["--rulebook", "/rulebooks/demo-rulebook.yaml", "--inventory", "/rulebooks/demo-inventory.yaml", "-vv"]
    volumeMounts:
    - name: rulebook-volume
      mountPath: /rulebooks
  volumes:
  - name: rulebook-volume
    configMap:
      name: eda-demo-rulebook
EOF

# Watch the demo
kubectl logs -f eda-demo-runner -n eda-server-operator-system
```

## Step 7: Verify AWX Job Ran

```bash
curl -s "$AWX_URL/api/v2/jobs/" -u "admin:$AWX_PASS" | jq '.results[] | {id, name, status}'
```

---

## Summary

| Component | Namespace | Version |
|-----------|-----------|---------|
| AWX Operator | awx | 2.19.1 |
| AWX | awx | 24.6.1 |
| EDA Operator | eda-server-operator-system | 1.0.2 |
| EDA Server | eda-server-operator-system | sha-ad278f8 |
| EDA UI | eda-server-operator-system | 2.6.4 |
| PostgreSQL | eda-server-operator-system | 15 |

## Cleanup

```bash
minikube delete
```
