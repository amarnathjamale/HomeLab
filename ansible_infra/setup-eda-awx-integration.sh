#!/bin/bash
#
# EDA-AWX Integration Setup Script
# Establishes communication between EDA and AWX in Kubernetes
#
# Usage: ./setup-eda-awx-integration.sh
#

set -e

# Configuration
AWX_NAMESPACE="${AWX_NAMESPACE:-awx}"
EDA_NAMESPACE="${EDA_NAMESPACE:-eda}"
AWX_SERVICE="awx-demo-service"
AWX_SECRET="awx-demo-admin-password"
EDA_SECRET="eda-admin-password"

echo "=============================================="
echo "  EDA-AWX Integration Setup"
echo "=============================================="
echo ""

#######################################
# Step 1: Verify AWX is running
#######################################
echo ">>> Step 1: Verifying AWX is running..."

if ! kubectl get svc ${AWX_SERVICE} -n ${AWX_NAMESPACE} &>/dev/null; then
  echo "ERROR: AWX service '${AWX_SERVICE}' not found in namespace '${AWX_NAMESPACE}'"
  exit 1
fi

AWX_URL="http://${AWX_SERVICE}.${AWX_NAMESPACE}.svc.cluster.local"
echo "  AWX URL: ${AWX_URL}"

# Get AWX password
AWX_PASS=$(kubectl get secret ${AWX_SECRET} -n ${AWX_NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
if [ -z "$AWX_PASS" ]; then
  echo "ERROR: Could not retrieve AWX admin password"
  exit 1
fi
echo "  AWX admin password retrieved"

#######################################
# Step 2: Verify EDA is running
#######################################
echo ""
echo ">>> Step 2: Verifying EDA is running..."

if ! kubectl get svc eda-api -n ${EDA_NAMESPACE} &>/dev/null; then
  echo "ERROR: EDA API service not found in namespace '${EDA_NAMESPACE}'"
  exit 1
fi

# Get EDA password
EDA_PASS=$(kubectl get secret ${EDA_SECRET} -n ${EDA_NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
if [ -z "$EDA_PASS" ]; then
  echo "ERROR: Could not retrieve EDA admin password"
  exit 1
fi
echo "  EDA admin password retrieved"

#######################################
# Step 3: Test AWX API connectivity from EDA
#######################################
echo ""
echo ">>> Step 3: Testing AWX API connectivity from EDA..."

EDA_API_POD=$(kubectl get pods -n ${EDA_NAMESPACE} -l app.kubernetes.io/component=eda-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || kubectl get pods -n ${EDA_NAMESPACE} | grep eda-api | head -1 | awk '{print $1}')

if [ -z "$EDA_API_POD" ]; then
  echo "ERROR: Could not find EDA API pod"
  exit 1
fi

echo "  EDA API Pod: ${EDA_API_POD}"

# Test connectivity
PING_RESULT=$(kubectl exec -n ${EDA_NAMESPACE} ${EDA_API_POD} -c eda-api -- curl -s -o /dev/null -w "%{http_code}" "${AWX_URL}/api/v2/ping/" 2>/dev/null || echo "failed")

if [ "$PING_RESULT" = "200" ] || [ "$PING_RESULT" = "301" ]; then
  echo "  AWX API is reachable from EDA (HTTP ${PING_RESULT})"
else
  echo "ERROR: Cannot reach AWX API from EDA pod (HTTP ${PING_RESULT})"
  echo "  Tried: ${AWX_URL}/api/v2/ping/"
  exit 1
fi

#######################################
# Step 4: Create AWX Token
#######################################
echo ""
echo ">>> Step 4: Creating AWX OAuth Token..."

# Find AWX web pod
AWX_WEB_POD=$(kubectl get pods -n ${AWX_NAMESPACE} -l app.kubernetes.io/component=awx-web -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || kubectl get pods -n ${AWX_NAMESPACE} | grep awx-web | grep -v task | head -1 | awk '{print $1}')

if [ -z "$AWX_WEB_POD" ]; then
  # Try alternate label
  AWX_WEB_POD=$(kubectl get pods -n ${AWX_NAMESPACE} | grep -E "awx.*web" | head -1 | awk '{print $1}')
fi

if [ -z "$AWX_WEB_POD" ]; then
  echo "ERROR: Could not find AWX web pod"
  exit 1
fi

echo "  AWX Web Pod: ${AWX_WEB_POD}"

# Create token via awx-manage
AWX_TOKEN=$(kubectl exec -n ${AWX_NAMESPACE} ${AWX_WEB_POD} -c awx-web -- awx-manage create_oauth2_token --user admin 2>/dev/null | tail -1)

if [ -z "$AWX_TOKEN" ]; then
  echo "  Creating token via API instead..."
  # Try via API
  AWX_TOKEN=$(kubectl exec -n ${EDA_NAMESPACE} ${EDA_API_POD} -c eda-api -- curl -s -X POST \
    -u "admin:${AWX_PASS}" \
    -H "Content-Type: application/json" \
    -d '{"description": "EDA Integration Token", "scope": "write"}' \
    "${AWX_URL}/api/v2/tokens/" 2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$AWX_TOKEN" ]; then
  echo "ERROR: Could not create AWX token"
  exit 1
fi

echo "  AWX Token created: ${AWX_TOKEN:0:10}..."

#######################################
# Step 5: Get EDA API Token
#######################################
echo ""
echo ">>> Step 5: Getting EDA API Token..."

# Port forward EDA API temporarily
kubectl port-forward svc/eda-api -n ${EDA_NAMESPACE} 8000:8000 &>/dev/null &
PF_PID=$!
sleep 3

# Get EDA auth token
EDA_TOKEN=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"admin\", \"password\": \"${EDA_PASS}\"}" \
  http://localhost:8000/api/eda/v1/auth/session/login/ 2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$EDA_TOKEN" ]; then
  # Try alternate auth endpoint
  EDA_TOKEN=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"admin\", \"password\": \"${EDA_PASS}\"}" \
    http://localhost:8000/api/v1/auth/token/ 2>/dev/null | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
fi

# Kill port forward
kill $PF_PID 2>/dev/null || true

if [ -z "$EDA_TOKEN" ]; then
  echo "  Could not get EDA token via API, will try direct DB approach..."
fi

#######################################
# Step 6: Create EDA Credential for AWX
#######################################
echo ""
echo ">>> Step 6: Creating EDA Credential for AWX Controller..."

# Get credential type ID for "Red Hat Ansible Automation Platform"
if [ -n "$EDA_TOKEN" ]; then
  kubectl port-forward svc/eda-api -n ${EDA_NAMESPACE} 8000:8000 &>/dev/null &
  PF_PID=$!
  sleep 3

  # Get credential type ID
  CRED_TYPE_ID=$(curl -s -H "Authorization: Token ${EDA_TOKEN}" \
    http://localhost:8000/api/eda/v1/credential-types/ 2>/dev/null | \
    grep -o '"id":[0-9]*,"name":"Red Hat Ansible Automation Platform"' | \
    grep -o '"id":[0-9]*' | cut -d: -f2)

  if [ -z "$CRED_TYPE_ID" ]; then
    # Try to find any controller credential type
    CRED_TYPE_ID=$(curl -s -H "Authorization: Token ${EDA_TOKEN}" \
      http://localhost:8000/api/eda/v1/credential-types/ 2>/dev/null | \
      grep -oE '"id":[0-9]+,"name":"[^"]*[Cc]ontroller[^"]*"' | head -1 | \
      grep -o '"id":[0-9]*' | cut -d: -f2)
  fi

  if [ -n "$CRED_TYPE_ID" ]; then
    echo "  Credential Type ID: ${CRED_TYPE_ID}"

    # Create the credential
    CRED_RESPONSE=$(curl -s -X POST \
      -H "Authorization: Token ${EDA_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"AWX Controller\",
        \"description\": \"AWX Controller for EDA integration\",
        \"credential_type_id\": ${CRED_TYPE_ID},
        \"inputs\": {
          \"host\": \"${AWX_URL}/\",
          \"oauth_token\": \"${AWX_TOKEN}\",
          \"verify_ssl\": false
        }
      }" \
      http://localhost:8000/api/eda/v1/eda-credentials/ 2>/dev/null)

    if echo "$CRED_RESPONSE" | grep -q '"id"'; then
      CRED_ID=$(echo "$CRED_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
      echo "  EDA Credential created successfully (ID: ${CRED_ID})"
    else
      echo "  Note: Credential may already exist or creation needs manual step"
      echo "  Response: ${CRED_RESPONSE}"
    fi
  else
    echo "  Could not find credential type, manual setup required"
  fi

  kill $PF_PID 2>/dev/null || true
else
  echo "  Skipping API credential creation (no EDA token)"
fi

#######################################
# Step 7: Save configuration
#######################################
echo ""
echo ">>> Step 7: Saving configuration..."

CONFIG_FILE="/tmp/eda-awx-integration.txt"
cat > ${CONFIG_FILE} << EOF
EDA-AWX Integration Configuration
=================================
Generated: $(date)

AWX Configuration:
  URL: ${AWX_URL}/
  Token: ${AWX_TOKEN}
  Namespace: ${AWX_NAMESPACE}
  Service: ${AWX_SERVICE}

EDA Configuration:
  Namespace: ${EDA_NAMESPACE}

Manual Setup (if needed):
-------------------------
1. Go to EDA UI -> Credentials -> Create credential
2. Credential Type: Red Hat Ansible Automation Platform
3. Name: AWX Controller
4. Controller URL: ${AWX_URL}/
5. OAuth Token: ${AWX_TOKEN}
6. Verify SSL: Unchecked
7. Save

Test Command:
-------------
kubectl exec -n ${EDA_NAMESPACE} ${EDA_API_POD} -c eda-api -- \\
  curl -H "Authorization: Bearer ${AWX_TOKEN}" "${AWX_URL}/api/v2/ping/"
EOF

echo "  Configuration saved to: ${CONFIG_FILE}"
cat ${CONFIG_FILE}

#######################################
# Summary
#######################################
echo ""
echo "=============================================="
echo "  Integration Setup Complete!"
echo "=============================================="
echo ""
echo "AWX Token: ${AWX_TOKEN}"
echo ""
echo "If credential was not auto-created, manually create in EDA UI:"
echo "  1. Credentials -> Create credential"
echo "  2. Type: Red Hat Ansible Automation Platform"
echo "  3. URL: ${AWX_URL}/"
echo "  4. Token: ${AWX_TOKEN}"
echo "  5. Verify SSL: Unchecked"
echo ""
