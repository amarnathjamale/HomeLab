# AWX and EDA Deployment on Minikube

## Quick Start

```bash
# Start minikube with adequate resources
minikube start --cpus=4 --memory=12288 --addons=ingress

# Deploy AWX
kubectl create namespace awx
kubectl apply -k awx-operator/
kubectl apply -f awx-operator/awx.yaml

# Deploy EDA (use main branch for latest fixes)
kubectl create namespace eda
kubectl apply -k eda-operator/
kubectl apply -f eda-operator/eda.yaml

# Access services (run in separate terminals)
kubectl port-forward svc/awx-demo-service -n awx 8080:80
kubectl port-forward svc/eda-ui -n eda 8081:80
```

## Issues We Faced and Solutions

### 1. EDA UI showing "Welcome to nginx!" default page

**Cause:** EDA operator 1.0.2 used `eda-ui:2.4.x` image which had UI files in `/opt/app-root/ui/eda/` but the nginx configuration pointed to `/usr/share/nginx/html`.

**Solution:** Update to operator `main` branch which uses `eda-ui:main` with files in the correct location.

### 2. EDA UI showing "AnsibleDev" instead of "Event-Driven Ansible"

**Cause:** Old `eda-ui:2.4.x` image was a generic "ansible-ui" without EDA branding.

**Solution:** Use newer `eda-ui:2.6.4` or `main` tag which has proper EDA branding.

### 3. No "Default" organization in EDA

**Cause:** EDA operator 1.0.2 with older eda-server didn't auto-create an organization.

**Solution:** Use operator `main` branch which auto-creates "Default" organization on first deployment.

### 4. Database migration errors when upgrading eda-server

**Cause:** Incompatible migrations between old DB schema and new `eda-server:main`.

**Solution:** Delete PVCs and redeploy fresh with new operator version:
```bash
kubectl delete eda eda -n eda
kubectl delete pvc -n eda --all
kubectl apply -f eda-operator/eda.yaml
```

## Credentials

### AWX
- **Username:** admin
- **Password:** Run `kubectl get secret awx-demo-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d`

### EDA
- **Username:** admin
- **Password:** Run `kubectl get secret eda-admin-password -n eda -o jsonpath='{.data.password}' | base64 -d`

## Demo Setup

The following resources have been created:

### In AWX:
- **Project:** Demo Project (ansible-tower-samples)
- **Inventory:** Demo Inventory with localhost
- **Job Templates:**
  - Demo Job Template (triggers hello_world.yml)
  - EDA Demo Job

### In EDA:
- **Project:** Demo EDA Project (event-driven-ansible examples)
- **Decision Environment:** Demo Decision Environment (ansible-rulebook:v1.1.1)
- **Rulebook Activations:**
  - Demo Hello Events Activation (range-based events)
  - Demo AWX Integration (triggers AWX job template)

## How the AWX-EDA Integration Works

1. EDA runs a rulebook that listens for events
2. When an event matches a rule condition, it triggers an action
3. The `run_job_template` action calls AWX API using the stored token
4. AWX executes the specified job template

### Example Rulebook (demo_controller_rulebook.yml):
```yaml
- name: Controller Demo
  hosts: all
  sources:
    - ansible.eda.range:
        limit: 5
  rules:
    - name: Controller Rule
      condition: event.i == 1
      action:
        run_job_template:
          name: Demo Job Template
          organization: Default
```

## Useful Commands

```bash
# Check all pods
kubectl get pods -n awx
kubectl get pods -n eda

# Check activation status
kubectl exec deployment/eda-api -n eda -c eda-api -- \
  curl -s "http://localhost:8000/api/eda/v1/activations/" \
  -u "admin:<password>"

# View AWX jobs triggered by EDA
curl -s "http://127.0.0.1:<awx-port>/api/v2/jobs/" \
  -u "admin:<password>" | jq '.results[] | {id, name, status}'

# View EDA logs
kubectl logs -f deployment/eda-api -n eda -c eda-api
kubectl logs -f deployment/eda-activation-worker -n eda
```

## File Structure

```
/Users/amar/eda/
├── awx-operator/
│   ├── kustomization.yaml    # AWX operator kustomization
│   └── awx.yaml              # AWX instance CR
├── eda-operator/
│   ├── kustomization.yaml    # EDA operator kustomization (use main branch!)
│   └── eda.yaml              # EDA instance CR
├── deploy-eda-complete.yaml  # Documented EDA CR with issue explanations
├── access-info.txt           # Quick reference for credentials
└── README.md                 # This file
```

## Key Learnings

1. **Always use latest operator versions** - The `main` branch of eda-server-operator has important fixes
2. **Image compatibility matters** - eda-server and eda-ui images must be compatible versions
3. **Fresh database for major upgrades** - When upgrading to a new operator version, delete PVCs first
4. **Minikube tunnel required on macOS** - Use `minikube service` command to access NodePort services
