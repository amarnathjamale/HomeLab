#!/bin/bash
# EDA Resource Provisioning Script
# Creates all EDA resources via API

set -e

EDA_URL="${EDA_URL:-http://eda-api.eda.svc.cluster.local:8000}"
EDA_USER="${EDA_USER:-admin}"
EDA_PASS="${EDA_PASS:-admin}"
AWX_TOKEN="${AWX_TOKEN:-}"

echo "=== EDA Resource Provisioning ==="
echo "EDA URL: $EDA_URL"

# Wait for EDA to be ready
echo "Waiting for EDA API..."
until curl -s -u "$EDA_USER:$EDA_PASS" "$EDA_URL/api/eda/v1/users/me/" | grep -q '"username"'; do
  echo "  EDA not ready, waiting..."
  sleep 10
done
echo "EDA API is ready!"

# Function to create resource
create_resource() {
  local endpoint=$1
  local data=$2
  local name=$3

  echo "Creating $name..."
  response=$(curl -s -X POST "$EDA_URL/api/eda/v1/$endpoint/" \
    -H "Content-Type: application/json" \
    -u "$EDA_USER:$EDA_PASS" \
    -d "$data")

  if echo "$response" | grep -q '"id"'; then
    id=$(echo "$response" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    echo "  Created $name (ID: $id)"
  else
    echo "  Warning: $name may already exist or failed"
    echo "  Response: $(echo $response | head -c 200)"
  fi
}

# Change admin password to 'admin'
echo "Setting admin password..."
kubectl exec deployment/eda-api -n eda -- aap-eda-manage update_password --username=admin --password=admin 2>/dev/null || true

# Create Decision Environment
create_resource "decision-environments" \
  '{"name": "Demo Decision Environment", "description": "Default DE for rulebooks", "image_url": "quay.io/ansible/ansible-rulebook:v1.1.1", "organization_id": 1, "pull_policy": "always"}' \
  "Decision Environment"

# Create Project
create_resource "projects" \
  '{"name": "Demo EDA Project", "description": "Sample rulebooks", "url": "https://github.com/ansible/event-driven-ansible", "organization_id": 1}' \
  "EDA Project"

echo "Waiting for project sync..."
sleep 30

# Create Event Stream Credential
create_resource "eda-credentials" \
  '{"name": "github-webhook-cred", "credential_type_id": 7, "organization_id": 1, "inputs": {"username": "github", "password": "webhook123", "auth_type": "basic", "http_header_key": "Authorization"}}' \
  "Event Stream Credential"

# Create Container Registry Credential
create_resource "eda-credentials" \
  '{"name": "Container Registry Cred", "credential_type_id": 2, "organization_id": 1, "inputs": {"host": "quay.io", "username": "myuser", "password": "mypassword"}}' \
  "Registry Credential"

# Create AWX Token (if provided)
if [ -n "$AWX_TOKEN" ]; then
  echo "Creating AWX Controller Token..."
  create_resource "users/me/awx-tokens" \
    "{\"name\": \"AWX Controller Token\", \"description\": \"Token for AWX integration\", \"token\": \"$AWX_TOKEN\"}" \
    "AWX Token"
fi

# Note: Event Streams require EVENT_STREAM_BASE_URL to be configured
# This is typically done through the EDA CR or environment variables

# Create Rulebook Activation (disabled)
echo "Creating Rulebook Activation..."
# Wait for project rulebooks to be available
sleep 10

# Get rulebook ID
rulebook_id=$(curl -s -u "$EDA_USER:$EDA_PASS" "$EDA_URL/api/eda/v1/rulebooks/" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
if [ -n "$rulebook_id" ]; then
  create_resource "activations" \
    "{\"name\": \"Demo Webhook Activation\", \"description\": \"Webhook event handler\", \"rulebook_id\": $rulebook_id, \"decision_environment_id\": 1, \"organization_id\": 1, \"is_enabled\": false}" \
    "Rulebook Activation"
fi

echo ""
echo "=== EDA Provisioning Complete ==="
echo "Login: admin / admin"
