# AWX and EDA Resources Created

## AWX Resources

### Organizations
| ID | Name | Description |
|----|------|-------------|
| 1 | Default | Default organization |
| 2 | Demo Organization | Example organization for demos |

### Teams
| ID | Name | Organization | Description |
|----|------|--------------|-------------|
| 1 | DevOps Team | Default | DevOps engineers team |

### Users
| ID | Username | Email | Superuser |
|----|----------|-------|-----------|
| 1 | admin | test@example.com | Yes |
| 2 | demouser | demo@example.com | No |

### Credentials
| ID | Name | Type | Description |
|----|------|------|-------------|
| 3 | Demo Machine Credential | Machine (SSH) | SSH credential for demo hosts |
| 4 | Demo SCM Credential | Source Control | Git credential for source control |
| 5 | Demo Vault Credential | Vault | Ansible Vault password |

### Projects
| ID | Name | SCM URL | Description |
|----|------|---------|-------------|
| 9 | Demo Ansible Project | https://github.com/ansible/ansible-tower-samples | Sample playbooks for demos |

### Inventories
| ID | Name | Organization | Hosts |
|----|------|--------------|-------|
| 1 | Demo Inventory | Default | 2 |

### Inventory Groups
| ID | Name | Inventory | Description |
|----|------|-----------|-------------|
| 1 | webservers | Demo Inventory | Web server hosts |

### Hosts
| ID | Name | Inventory | Description |
|----|------|-----------|-------------|
| 1 | localhost | Demo Inventory | Local execution |
| 2 | webserver1.example.com | Demo Inventory | Primary web server |

### Inventory Sources
| ID | Name | Source | Project |
|----|------|--------|---------|
| 10 | Demo SCM Source | scm | Demo Ansible Project |

### Job Templates
| ID | Name | Project | Playbook | Survey |
|----|------|---------|----------|--------|
| 7 | Demo Job Template | - | hello_world.yml | No |
| 11 | Hello World Job | Demo Ansible Project | hello_world.yml | Yes |

### Workflow Job Templates
| ID | Name | Description | Nodes |
|----|------|-------------|-------|
| 12 | Demo Workflow | Example workflow with multiple steps | 1 |

### Schedules
| ID | Name | Template | RRULE | Enabled |
|----|------|----------|-------|---------|
| 6 | Daily Hello World | Hello World Job | FREQ=DAILY at 9am | No |

### Notification Templates
| ID | Name | Type | Description |
|----|------|------|-------------|
| 1 | Email Notification | Email | Send email on job completion |

### Execution Environments
| ID | Name | Image |
|----|------|-------|
| 4 | Demo Execution Environment | quay.io/ansible/awx-ee:latest |

### OAuth Applications
| ID | Name | Grant Type | Description |
|----|------|------------|-------------|
| 1 | EDA Application | password | OAuth app for EDA integration |

### Tokens
| ID | Description | Scope |
|----|-------------|-------|
| 2 | GitHub Webhook Runner | write |

---

## EDA Resources

### Organizations
| ID | Name | Description |
|----|------|-------------|
| 1 | Default | The default organization |

### Projects
| ID | Name | URL | Description |
|----|------|-----|-------------|
| 1 | Demo EDA Project | https://github.com/ansible/event-driven-ansible | Demo project with sample rulebooks |

### Decision Environments
| ID | Name | Image |
|----|------|-------|
| 1 | Demo Decision Environment | quay.io/ansible/ansible-rulebook:v1.1.1 |

### EDA Credentials
| ID | Name | Type | Description |
|----|------|------|-------------|
| 2 | github-webhook-cred | Basic Event Stream | For webhook authentication |
| 3 | Container Registry Cred | Container Registry | quay.io registry access |

### AWX Controller Tokens
| ID | Name | Description |
|----|------|-------------|
| 2 | AWX Controller Token | Token for AWX integration |

### Event Streams
| ID | Name | Type | Webhook URL |
|----|------|------|-------------|
| 1 | github-events | Basic | http://192.168.49.2:30082/api/eda/v1/external_event_stream/86488586-713f-48e4-ae06-71ef7ee16cae/post/ |

### Rulebook Activations
| ID | Name | Rulebook | Decision Environment | Enabled |
|----|------|----------|----------------------|---------|
| 3 | Demo Webhook Activation | demo_webhook_rulebook.yml | Demo Decision Environment | No |

### Available Rulebooks (from Demo EDA Project)
| ID | Name |
|----|------|
| 1 | github-ci-cd-rules.yml |
| 2 | demo_rulebook.yml |
| 3 | local-test-rules.yml |
| 4 | git-hook-deploy-rules.yml |
| 5 | process_down.yml |
| 6 | journald_events.yml |
| 7 | demo_controller_rulebook.yml |
| 8 | kafka-test-rules.yml |
| 9 | hello_events.yml |
| 10 | demo_webhook_rulebook.yml |

---

## Access Information

### AWX
- **URL**: `kubectl port-forward svc/awx-service -n awx 8080:80`
- **Username**: admin
- **Password**: admin

### EDA
- **URL**: `kubectl port-forward svc/eda-ui -n eda 8081:80`
- **Username**: admin
- **Password**: admin

### Event Stream Webhook
- **URL**: http://192.168.49.2:30082/api/eda/v1/external_event_stream/86488586-713f-48e4-ae06-71ef7ee16cae/post/
- **Auth**: Basic (github:webhook123)

---

## Manual Webhook Runner (Standalone)

Running in namespace `eda`:
- **Pod**: github-webhook-runner
- **Service**: github-webhook-runner:5000
- **Rulebook**: github-webhook-rulebook.yaml

Test command:
```bash
kubectl exec deployment/eda-api -n eda -- curl -X POST http://github-webhook-runner:5000/endpoint \
  -H "Content-Type: application/json" \
  -d '{"ref": "refs/heads/main", "after": "abc123"}'
```
