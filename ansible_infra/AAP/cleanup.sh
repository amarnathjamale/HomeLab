#!/bin/bash
#
# AAP Cleanup Script
# Removes all AWX and EDA resources
#
# Usage: ./cleanup.sh [--full]  (--full also deletes minikube)
#

set -e

FULL_CLEANUP=false

if [ "$1" = "--full" ]; then
  FULL_CLEANUP=true
fi

echo "=============================================="
echo "  Ansible Automation Platform Cleanup"
echo "=============================================="
echo ""

# Delete EDA
echo ">>> Removing EDA..."
kubectl delete eda eda -n eda 2>/dev/null || true
kubectl delete pvc --all -n eda 2>/dev/null || true
kubectl delete namespace eda 2>/dev/null || true

# Delete AWX
echo ">>> Removing AWX..."
kubectl delete awx awx -n awx 2>/dev/null || true
kubectl delete pvc --all -n awx 2>/dev/null || true
kubectl delete namespace awx 2>/dev/null || true

echo ""
echo "Cleanup complete!"

if [ "$FULL_CLEANUP" = true ]; then
  echo ""
  echo ">>> Deleting Minikube..."
  minikube delete
fi
