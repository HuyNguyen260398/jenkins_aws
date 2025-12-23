#!/bin/bash
# Deploy Jenkins to EKS cluster

STACK_NAME="jenkins-eks-stack-v2"
CLUSTER_NAME="jenkins-eks-cluster"
REGION="ap-southeast-1"
NAMESPACE="jenkins"

echo "=========================================="
echo "Jenkins EKS Deployment Script"
echo "=========================================="

# Step 1: Wait for CloudFormation stack to complete
echo ""
echo "Waiting for CloudFormation stack to complete..."
aws cloudformation wait stack-create-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION" 2>/dev/null || true

STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null)

if [ "$STACK_STATUS" != "CREATE_COMPLETE" ]; then
    echo "Stack status: $STACK_STATUS"
    echo "Waiting for stack completion..."
    sleep 30
fi

# Step 2: Configure kubectl
echo ""
echo "Configuring kubectl..."
aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$REGION"

# Step 3: Wait for nodes to be ready
echo ""
echo "Waiting for Kubernetes nodes to be ready..."
for i in {1..60}; do
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$NODE_COUNT" -ge 1 ]; then
        echo "✓ Nodes are ready!"
        break
    fi
    echo "Waiting for nodes... ($i/60)"
    sleep 10
done

# Step 4: Deploy Jenkins manifests
echo ""
echo "Deploying Jenkins..."
kubectl apply -f jenkins-deployment.yaml

# Step 5: Wait for Jenkins pod to be ready
echo ""
echo "Waiting for Jenkins pod to start..."
kubectl wait --for=condition=Ready pod \
  -l app=jenkins \
  -n jenkins \
  --timeout=600s 2>/dev/null || true

# Step 6: Get Jenkins access information
echo ""
echo "=========================================="
echo "Jenkins Deployment Complete!"
echo "=========================================="
echo ""

# Get LoadBalancer endpoint
JENKINS_LB=$(kubectl get svc -n jenkins jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$JENKINS_LB" ]; then
    echo "⏳ Waiting for LoadBalancer to be assigned..."
    sleep 30
    JENKINS_LB=$(kubectl get svc -n jenkins jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
fi

if [ -n "$JENKINS_LB" ]; then
    echo "✓ Jenkins is accessible at: http://$JENKINS_LB"
else
    echo "⚠ LoadBalancer endpoint not yet assigned. Check with:"
    echo "  kubectl get svc -n jenkins jenkins"
fi

# Get initial admin password
echo ""
echo "Getting initial admin password..."
sleep 5
JENKINS_POD=$(kubectl get pods -n jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$JENKINS_POD" ]; then
    echo "Jenkins Pod: $JENKINS_POD"
    echo ""
    echo "To get the initial admin password, run:"
    echo "  kubectl exec -n jenkins $JENKINS_POD -- cat /var/jenkins_home/secrets/initialAdminPassword"
else
    echo "Jenkins pod not yet ready. Try again in a moment."
fi

echo ""
echo "=========================================="
echo "Deployment Details:"
echo "=========================================="
kubectl get all -n jenkins
