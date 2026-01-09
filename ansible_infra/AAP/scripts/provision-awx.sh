#!/bin/bash
# AWX Resource Provisioning Script
# Creates all AWX resources via API

set -e

AWX_URL="${AWX_URL:-http://awx-demo-service.awx.svc.cluster.local:80}"
AWX_USER="${AWX_USER:-admin}"
AWX_PASS="${AWX_PASS:-admin}"

echo "=== AWX Resource Provisioning ==="
echo "AWX URL: $AWX_URL"

# Wait for AWX to be ready
echo "Waiting for AWX API..."
until curl -s -u "$AWX_USER:$AWX_PASS" "$AWX_URL/api/v2/ping/" | grep -q "version"; do
  echo "  AWX not ready, waiting..."
  sleep 10
done
echo "AWX API is ready!"

# Function to create resource
create_resource() {
  local endpoint=$1
  local data=$2
  local name=$3

  echo "Creating $name..."
  response=$(curl -s -X POST "$AWX_URL/api/v2/$endpoint/" \
    -H "Content-Type: application/json" \
    -u "$AWX_USER:$AWX_PASS" \
    -d "$data")

  if echo "$response" | grep -q '"id"'; then
    id=$(echo "$response" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    echo "  Created $name (ID: $id)"
  else
    echo "  Warning: $name may already exist or failed"
    echo "  Response: $response"
  fi
}

# Change admin password to 'admin'
echo "Setting admin password..."
curl -s -X POST "$AWX_URL/api/v2/users/1/" \
  -H "Content-Type: application/json" \
  -u "$AWX_USER:$AWX_PASS" \
  -d '{"password": "admin"}' > /dev/null 2>&1 || true

# Create Organization
create_resource "organizations" \
  '{"name": "Demo Organization", "description": "Example organization for demos"}' \
  "Demo Organization"

# Create Team
create_resource "teams" \
  '{"name": "DevOps Team", "description": "DevOps engineers team", "organization": 1}' \
  "DevOps Team"

# Create User
create_resource "users" \
  '{"username": "demouser", "password": "demopass123", "email": "demo@example.com", "first_name": "Demo", "last_name": "User"}' \
  "Demo User"

# Create Credentials
create_resource "credentials" \
  '{"name": "Demo Machine Credential", "description": "SSH credential", "organization": 1, "credential_type": 1, "inputs": {"username": "ansible", "password": "ansible123"}}' \
  "Machine Credential"

create_resource "credentials" \
  '{"name": "Demo SCM Credential", "description": "Git credential", "organization": 1, "credential_type": 2, "inputs": {"username": "git", "password": "gitpassword"}}' \
  "SCM Credential"

create_resource "credentials" \
  '{"name": "Demo Vault Credential", "description": "Vault password", "organization": 1, "credential_type": 3, "inputs": {"vault_password": "vaultpass123"}}' \
  "Vault Credential"

# Create Project
create_resource "projects" \
  '{"name": "Demo Ansible Project", "description": "Sample playbooks", "organization": 1, "scm_type": "git", "scm_url": "https://github.com/ansible/ansible-tower-samples", "scm_branch": "master"}' \
  "Demo Project"

echo "Waiting for project sync..."
sleep 30

# Create Inventory
create_resource "inventories" \
  '{"name": "Demo Inventory", "description": "Demo hosts inventory", "organization": 1}' \
  "Demo Inventory"

# Create Group
create_resource "groups" \
  '{"name": "webservers", "description": "Web server hosts", "inventory": 1}' \
  "Inventory Group"

# Create Hosts
create_resource "hosts" \
  '{"name": "localhost", "description": "Local execution", "inventory": 1, "variables": "ansible_connection: local"}' \
  "localhost"

create_resource "hosts" \
  '{"name": "webserver1.example.com", "description": "Web server", "inventory": 1, "variables": "ansible_host: 192.168.1.10\nansible_user: ansible"}' \
  "webserver1"

# Create Job Template
create_resource "job_templates" \
  '{"name": "Demo Job Template", "description": "Hello world playbook", "organization": 1, "project": 6, "playbook": "hello_world.yml", "inventory": 1, "job_type": "run"}' \
  "Demo Job Template"

# Create Workflow
create_resource "workflow_job_templates" \
  '{"name": "Demo Workflow", "description": "Example workflow", "organization": 1}' \
  "Demo Workflow"

# Create Notification Template
create_resource "notification_templates" \
  '{"name": "Email Notification", "description": "Email on completion", "organization": 1, "notification_type": "email", "notification_configuration": {"host": "smtp.example.com", "port": 587, "username": "awx@example.com", "password": "emailpass", "sender": "awx@example.com", "recipients": ["admin@example.com"], "use_tls": true, "use_ssl": false}}' \
  "Email Notification"

# Create Execution Environment
create_resource "execution_environments" \
  '{"name": "Demo Execution Environment", "description": "Custom EE", "organization": 1, "image": "quay.io/ansible/awx-ee:latest"}' \
  "Execution Environment"

# Create OAuth Application
create_resource "applications" \
  '{"name": "EDA Application", "description": "OAuth for EDA", "organization": 1, "authorization_grant_type": "password", "client_type": "confidential"}' \
  "OAuth Application"

# Create Token for EDA
echo "Creating EDA Token..."
token_response=$(curl -s -X POST "$AWX_URL/api/v2/tokens/" \
  -H "Content-Type: application/json" \
  -u "$AWX_USER:$AWX_PASS" \
  -d '{"description": "EDA Integration Token", "scope": "write"}')

if echo "$token_response" | grep -q '"token"'; then
  token=$(echo "$token_response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  echo "  EDA Token: $token"
  echo "$token" > /tmp/awx-token.txt
else
  echo "  Token creation may have failed"
fi

echo ""
echo "=== AWX Provisioning Complete ==="
echo "Login: admin / admin"
