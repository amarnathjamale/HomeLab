# Ansible Automation Platform (AAP) on Kubernetes

Complete deployment of AWX and Event-Driven Ansible (EDA) on Minikube with all resources pre-configured.

## Quick Start

```bash
# Make scripts executable
chmod +x deploy.sh cleanup.sh

# Deploy everything
./deploy.sh

# Access UIs (run in separate terminals)
kubectl port-forward svc/awx-service -n awx 8080:80
kubectl port-forward svc/eda-ui -n eda 8081:80
```

## Folder Structure

```
AAP/
├── awx/                          # AWX Deployment
│   ├── namespace.yaml            # AWX namespace
│   ├── kustomization.yaml        # AWX operator kustomization
│   └── awx-instance.yaml         # AWX CR instance
│
├── eda/                          # EDA Deployment
│   ├── namespace.yaml            # EDA namespace
│   ├── kustomization.yaml        # EDA operator kustomization
│   └── eda-instance.yaml         # EDA CR instance
│
├── resources/                    # Resource Provisioning
│   ├── awx-resources.yaml        # AWX resources ConfigMap
│   ├── eda-resources.yaml        # EDA resources ConfigMap
│   ├── provisioning-job.yaml     # AWX provisioning Job
│   └── eda-provisioning-job.yaml # EDA provisioning Job
│
├── scripts/                      # Standalone Scripts
│   ├── provision-awx.sh          # AWX provisioning script
│   └── provision-eda.sh          # EDA provisioning script
│
├── deploy.sh                     # Master deployment script
├── cleanup.sh                    # Cleanup script
└── README.md                     # This file
```

## Components Deployed

### AWX Resources
| Resource | Name | Description |
|----------|------|-------------|
| Organization | Demo Organization | Example organization |
| Team | DevOps Team | DevOps engineers team |
| User | demouser | Demo user account |
| Credential | Demo Machine Credential | SSH credential |
| Credential | Demo SCM Credential | Git credential |
| Credential | Demo Vault Credential | Ansible Vault |
| Project | Demo Ansible Project | Sample playbooks |
| Inventory | Demo Inventory | Demo hosts |
| Group | webservers | Inventory group |
| Host | localhost | Local execution |
| Host | webserver1.example.com | Example host |
| Job Template | Demo Job Template | Hello world |
| Workflow | Demo Workflow | Example workflow |
| Notification | Email Notification | Email template |
| Execution Env | Demo Execution Environment | Custom EE |
| Application | EDA Application | OAuth app |

### EDA Resources
| Resource | Name | Description |
|----------|------|-------------|
| Decision Env | Demo Decision Environment | Rulebook runner |
| Project | Demo EDA Project | Sample rulebooks |
| Credential | github-webhook-cred | Event stream auth |
| Credential | Container Registry Cred | Registry access |
| Activation | Demo Webhook Activation | Webhook handler |

## Deployment Options

```bash
# Full deployment
./deploy.sh

# Skip minikube setup (if already running)
./deploy.sh --skip-minikube

# Deploy only AWX
./deploy.sh --skip-eda --skip-resources

# Deploy only EDA (requires AWX for integration)
./deploy.sh --skip-awx --skip-resources

# Skip resource provisioning
./deploy.sh --skip-resources
```

## Manual Step-by-Step Deployment

### 1. Start Minikube
```bash
minikube start --cpus=4 --memory=12288 --addons=ingress
kubectl config use-context minikube
```

### 2. Deploy AWX
```bash
# Install operator
kubectl apply -k awx/

# Wait for operator
kubectl wait --for=condition=Available deployment/awx-operator-controller-manager -n awx --timeout=180s

# Deploy AWX instance
kubectl apply -f awx/awx-instance.yaml

# Wait for AWX (3-5 minutes)
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=awx-web -n awx --timeout=600s

# Get password
kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d
```

### 3. Deploy EDA
```bash
# Install operator
kubectl apply -k eda/

# Wait for operator
kubectl wait --for=condition=Available deployment -l control-plane=controller-manager -n eda --timeout=180s

# Deploy EDA instance
kubectl apply -f eda/eda-instance.yaml

# Wait for EDA (2-3 minutes)
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=eda-api -n eda --timeout=600s

# Get password
kubectl get secret eda-admin-password -n eda -o jsonpath='{.data.password}' | base64 -d
```

### 4. Provision Resources
```bash
# AWX resources
kubectl apply -f resources/awx-resources.yaml
kubectl apply -f resources/provisioning-job.yaml
kubectl logs -f job/awx-provision -n awx

# EDA resources
kubectl apply -f resources/eda-resources.yaml
kubectl apply -f resources/eda-provisioning-job.yaml
kubectl logs -f job/eda-provision -n eda
```

## Credentials

| Service | Username | Password |
|---------|----------|----------|
| AWX | admin | admin (after provisioning) |
| EDA | admin | (from secret, or set to 'admin') |
| demouser | demouser | demopass123 |

### Change EDA Password
```bash
kubectl exec deployment/eda-api -n eda -- aap-eda-manage update_password --username=admin --password=admin
```

## Cleanup

```bash
# Remove AWX and EDA
./cleanup.sh

# Remove everything including minikube
./cleanup.sh --full
```

## Versions

| Component | Version |
|-----------|---------|
| AWX Operator | 2.19.1 |
| AWX | 24.6.1 |
| EDA Operator | main |
| EDA Server | main |
| EDA UI | main |

## Troubleshooting

### Check pod status
```bash
kubectl get pods -n awx
kubectl get pods -n eda
```

### View logs
```bash
# AWX
kubectl logs deployment/awx-operator-controller-manager -n awx
kubectl logs deployment/awx-task -n awx
kubectl logs deployment/awx-web -n awx

# EDA
kubectl logs deployment/eda-server-operator-controller-manager -n eda
kubectl logs deployment/eda-api -n eda
```

### Reset deployment
```bash
# Reset AWX
kubectl delete awx awx -n awx
kubectl delete pvc --all -n awx
kubectl apply -f awx/awx-instance.yaml

# Reset EDA
kubectl delete eda eda -n eda
kubectl delete pvc --all -n eda
kubectl apply -f eda/eda-instance.yaml
```
