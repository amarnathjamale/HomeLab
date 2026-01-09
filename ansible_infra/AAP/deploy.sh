#!/bin/bash
#
# AAP Complete Deployment Script
# Deploys AWX, EDA, and all resources on Kubernetes
#
# Usage: ./deploy.sh [--skip-awx] [--skip-eda] [--skip-resources]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_AWX=false
SKIP_EDA=false
SKIP_RESOURCES=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --skip-awx) SKIP_AWX=true ;;
    --skip-eda) SKIP_EDA=true ;;
    --skip-resources) SKIP_RESOURCES=true ;;
    --help)
      echo "Usage: ./deploy.sh [OPTIONS]"
      echo "Options:"
      echo "  --skip-awx        Skip AWX deployment"
      echo "  --skip-eda        Skip EDA deployment"
      echo "  --skip-resources  Skip resource provisioning"
      exit 0
      ;;
  esac
done

echo "=============================================="
echo "  Ansible Automation Platform Deployment"
echo "=============================================="
echo ""

#######################################
# Step 1: Deploy AWX
#######################################
if [ "$SKIP_AWX" = false ]; then
  echo ">>> Step 1: Deploying AWX..."

  # Create namespace
  echo "  Creating AWX namespace..."
  kubectl create namespace awx 2>/dev/null || true

  # Deploy AWX operator
  echo "  Installing AWX Operator..."
  kubectl apply -k "$SCRIPT_DIR/awx/"

  # Wait for operator
  echo "  Waiting for AWX Operator..."
  kubectl wait --for=condition=Available deployment/awx-operator-controller-manager -n awx --timeout=180s

  # Deploy AWX instance
  echo "  Deploying AWX Instance..."
  kubectl apply -f "$SCRIPT_DIR/awx/awx-instance.yaml"

  # Wait for AWX
  echo "  Waiting for AWX to be ready (this may take 3-5 minutes)..."
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=awx-web -n awx --timeout=600s || true
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=awx-task -n awx --timeout=600s || true

  # Get AWX password
  AWX_PASS=$(kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d)
  echo ""
  echo "  AWX Deployed!"
  echo "  Initial Password: $AWX_PASS"
  echo ""
fi

#######################################
# Step 2: Deploy EDA
#######################################
if [ "$SKIP_EDA" = false ]; then
  echo ">>> Step 2: Deploying EDA..."

  # Create namespace
  echo "  Creating EDA namespace..."
  kubectl create namespace eda 2>/dev/null || true

  # Deploy EDA operator
  echo "  Installing EDA Operator..."
  kubectl apply -k "$SCRIPT_DIR/eda/"

  # Wait for operator
  echo "  Waiting for EDA Operator..."
  kubectl wait --for=condition=Available deployment -l control-plane=controller-manager -n eda --timeout=180s || true

  # Deploy EDA instance
  echo "  Deploying EDA Instance..."
  kubectl apply -f "$SCRIPT_DIR/eda/eda-instance.yaml"

  # Wait for EDA
  echo "  Waiting for EDA to be ready (this may take 2-3 minutes)..."
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=eda-api -n eda --timeout=600s || true

  # Get EDA password
  EDA_PASS=$(kubectl get secret eda-admin-password -n eda -o jsonpath='{.data.password}' | base64 -d)
  echo ""
  echo "  EDA Deployed!"
  echo "  Initial Password: $EDA_PASS"
  echo ""
fi

#######################################
# Step 3: Provision Resources (Config as Code)
#######################################
if [ "$SKIP_RESOURCES" = false ]; then
  echo ">>> Step 3: Provisioning Resources using Ansible Runner Pod..."

  # Clean up any existing runner resources
  echo "  Cleaning up existing provisioning resources..."
  kubectl delete pod ansible-runner --ignore-not-found 2>/dev/null || true
  kubectl delete configmap ansible-playbooks --ignore-not-found 2>/dev/null || true

  # Deploy ansible-runner pod (runs playbooks from inside the cluster)
  echo "  Deploying Ansible Runner Pod..."
  kubectl apply -f "$SCRIPT_DIR/playbooks/ansible-runner-pod.yaml"

  # Wait for pod to complete
  echo "  Waiting for provisioning to complete (this may take 2-3 minutes)..."
  kubectl wait --for=condition=Ready pod/ansible-runner --timeout=60s 2>/dev/null || true

  # Follow logs until completion
  echo "  Provisioning in progress..."
  kubectl logs -f ansible-runner 2>/dev/null || true

  # Check final status
  POD_STATUS=$(kubectl get pod ansible-runner -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  if [ "$POD_STATUS" = "Succeeded" ]; then
    echo "  Provisioning completed successfully!"
  else
    echo "  Provisioning status: $POD_STATUS"
    echo "  Check logs with: kubectl logs ansible-runner"
  fi

  echo ""
fi

#######################################
# Summary
#######################################
echo "=============================================="
echo "  Deployment Complete!"
echo "=============================================="
echo ""
echo "Access the UIs (run in separate terminals):"
echo ""
echo "  AWX:  kubectl port-forward svc/awx-service -n awx 8080:80"
echo "  EDA:  kubectl port-forward svc/eda-ui -n eda 8081:80"
echo ""
echo "Credentials:"
echo "  AWX:  admin / admin"
echo "  EDA:  admin / admin"
echo ""
