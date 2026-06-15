#!/bin/bash

# MCP Production Agent Stacks - One-Command Deploy
# 
# Prerequisites:
# - Google Cloud SDK installed and authenticated
# - kubectl configured
# - Terraform installed
#
# Usage: ./scripts/deploy.sh

set -e

echo "🚀 Deploying MCP Production Agent Stacks..."

# Configuration
PROJECT_ID="${PROJECT_ID:-your-gcp-project}"
REGION="${REGION:-us-central1}"
CLUSTER_NAME="mcp-agent-cluster"

# Step 1: Enable required APIs
echo "📦 Enabling Google Cloud APIs..."
gcloud services enable container.googleapis.com \
  compute.googleapis.com \
  secretmanager.googleapis.com \
  monitoring.googleapis.com \
  --project "$PROJECT_ID"

# Step 2: Deploy Terraform infrastructure
echo "🏗️  Provisioning infrastructure with Terraform..."
cd terraform
terraform init
terraform apply -auto-approve \
  -var="project_id=$PROJECT_ID" \
  -var="region=$REGION" \
  -var="cluster_name=$CLUSTER_NAME"
cd ..

# Step 3: Get cluster credentials
echo "🔐 Configuring kubectl..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region "$REGION" \
  --project "$PROJECT_ID"

# Step 4: Deploy MCP servers
echo "🤖 Deploying MCP servers..."
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/mcp-server-deployment.yaml
kubectl apply -f kubernetes/mcp-server-service.yaml
kubectl apply -f kubernetes/hpa.yaml

# Step 5: Deploy monitoring stack
echo "📊 Setting up monitoring..."
kubectl apply -f kubernetes/monitoring/

# Step 6: Wait for deployment
echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available deployment/mcp-server -n mcp --timeout=300s

# Step 7: Get external IP
echo "✅ Deployment complete!"
echo ""
echo "MCP Server Endpoint:"
kubectl get svc mcp-server -n mcp -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo ""
echo ""
echo "Next steps:"
echo "1. Update your AI agent config to point to the MCP server endpoint"
echo "2. Configure API keys in Google Secret Manager"
echo "3. Check Grafana dashboards for monitoring"
echo ""
echo "🎉 Bold ideas wait for no one!"
