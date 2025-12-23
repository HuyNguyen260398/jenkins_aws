#!/bin/bash

# Jenkins EKS Deployment Script
# This script deploys Jenkins on AWS EKS in ap-southeast-1

set -e

REGION="ap-southeast-1"
STACK_NAME="jenkins-eks-stack"
CLUSTER_NAME="jenkins-eks-cluster"
KUBERNETES_VERSION="1.28"

echo "=========================================="
echo "Jenkins EKS Deployment Script"
echo "Region: $REGION"
echo "Stack Name: $STACK_NAME"
echo "=========================================="

# Step 1: Validate CloudFormation template
echo ""
echo "Step 1: Validating CloudFormation template..."
aws cloudformation validate-template \
  --template-body file://jenkins-eks-stack.yaml \
  --region $REGION

# Step 2: Create CloudFormation Stack
echo ""
echo "Step 2: Creating CloudFormation stack..."
aws cloudformation create-stack \
  --stack-name $STACK_NAME \
  --template-body file://jenkins-eks-stack.yaml \
  --parameters \
    ParameterKey=ClusterName,ParameterValue=$CLUSTER_NAME \
    ParameterKey=DesiredNodeCapacity,ParameterValue=2 \
    ParameterKey=NodeInstanceType,ParameterValue=t3.medium \
  --capabilities CAPABILITY_IAM \
  --region $REGION

# Step 3: Wait for stack creation
echo ""
echo "Step 3: Waiting for CloudFormation stack creation (this may take 15-20 minutes)..."
aws cloudformation wait stack-create-complete \
  --stack-name $STACK_NAME \
  --region $REGION

echo "Stack created successfully!"

# Step 4: Get cluster endpoint
echo ""
echo "Step 4: Retrieving cluster information..."
CLUSTER_INFO=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query 'cluster.[endpoint,name,status]' \
  --output text)

echo "Cluster Info: $CLUSTER_INFO"

# Step 5: Configure kubectl
echo ""
echo "Step 5: Configuring kubectl..."
aws eks update-kubeconfig \
  --name $CLUSTER_NAME \
  --region $REGION

# Step 6: Verify cluster connectivity
echo ""
echo "Step 6: Verifying cluster connectivity..."
kubectl cluster-info
kubectl get nodes

# Step 7: Install AWS EBS CSI Driver (required for persistent volumes)
echo ""
echo "Step 7: Installing AWS EBS CSI Driver..."
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.20"

# Wait for EBS CSI Driver to be ready
echo "Waiting for EBS CSI Driver to be ready..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-ebs-csi-driver \
  -n kube-system \
  --timeout=300s || true

# Step 8: Deploy Jenkins
echo ""
echo "Step 8: Deploying Jenkins..."
kubectl apply -f jenkins-deployment.yaml

# Step 9: Wait for Jenkins to be ready
echo ""
echo "Step 9: Waiting for Jenkins pod to be ready (this may take 2-3 minutes)..."
kubectl wait --for=condition=ready pod \
  -l app=jenkins \
  -n jenkins \
  --timeout=600s || true

# Step 10: Get LoadBalancer endpoint
echo ""
echo "Step 10: Retrieving Jenkins LoadBalancer endpoint..."
JENKINS_LB_ENDPOINT=""
RETRY_COUNT=0
MAX_RETRIES=30

while [ -z "$JENKINS_LB_ENDPOINT" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  JENKINS_LB_ENDPOINT=$(kubectl get svc jenkins \
    -n jenkins \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  
  if [ -z "$JENKINS_LB_ENDPOINT" ]; then
    echo "Waiting for LoadBalancer endpoint to be assigned... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT + 1))
  fi
done

if [ -z "$JENKINS_LB_ENDPOINT" ]; then
  echo "Warning: LoadBalancer endpoint not yet available. Please check later with:"
  echo "  kubectl get svc jenkins -n jenkins"
else
  echo "Jenkins is available at: http://$JENKINS_LB_ENDPOINT"
fi

# Step 11: Get initial admin password
echo ""
echo "Step 11: Retrieving Jenkins initial admin password..."
echo "Run the following command to get the initial admin password:"
echo "  kubectl exec -it -n jenkins \$(kubectl get pod -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}') -- cat /var/jenkins_home/secrets/initialAdminPassword"

echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo "Region: $REGION"
echo "Cluster Name: $CLUSTER_NAME"
echo "Stack Name: $STACK_NAME"
echo "Jenkins URL: http://$JENKINS_LB_ENDPOINT (if available)"
echo ""
echo "Next Steps:"
echo "1. Wait for the LoadBalancer endpoint to be assigned"
echo "2. Access Jenkins at: http://<JENKINS_LB_ENDPOINT>"
echo "3. Retrieve the initial admin password using the command above"
echo "4. Complete Jenkins setup wizard"
echo "=========================================="
