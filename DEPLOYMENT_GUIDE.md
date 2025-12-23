# Jenkins EKS Deployment Guide

## Overview
This guide provides step-by-step instructions to deploy Jenkins on AWS EKS (Elastic Kubernetes Service) in the `ap-southeast-1` region with a public LoadBalancer endpoint.

## Architecture

The deployment includes:
- **VPC**: Custom VPC with CIDR block `10.0.0.0/16`
- **Subnets**: 2 public subnets and 2 private subnets across 2 availability zones (ap-southeast-1a, ap-southeast-1b)
- **EKS Cluster**: Kubernetes cluster with version 1.28
- **Node Group**: 2 t3.medium nodes (configurable)
- **Storage**: 20GB EBS volume for Jenkins persistent storage
- **LoadBalancer Service**: Public endpoint to access Jenkins
- **Security Groups**: Properly configured for cluster, worker nodes, and LoadBalancer

## Prerequisites

Before deploying, ensure you have:

1. **AWS Account**: Active AWS account with appropriate permissions
2. **AWS CLI**: Installed and configured
   ```bash
   aws --version
   aws configure
   ```
3. **kubectl**: Installed (v1.28 or later)
   ```bash
   kubectl version --client
   ```
4. **IAM Permissions**: The following IAM permissions are required:
   - CloudFormation: CreateStack, DescribeStacks, UpdateStack, DeleteStack
   - EKS: CreateCluster, DescribeCluster, CreateNodegroup, DescribeNodegroup
   - EC2: CreateVpc, CreateSubnet, CreateSecurityGroup, CreateInternetGateway, etc.
   - IAM: CreateRole, AttachRolePolicy
   - S3: (optional) For CloudFormation template storage

## Deployment Steps

### Step 1: Prepare the Environment

```bash
# Navigate to the deployment directory
cd c:\Workspace\jenkins_aws

# Verify CloudFormation template
aws cloudformation validate-template \
  --template-body file://jenkins-eks-stack.yaml \
  --region ap-southeast-1
```

### Step 2: Create the CloudFormation Stack

```bash
# Create the EKS cluster and infrastructure
aws cloudformation create-stack \
  --stack-name jenkins-eks-stack \
  --template-body file://jenkins-eks-stack.yaml \
  --parameters \
    ParameterKey=ClusterName,ParameterValue=jenkins-eks-cluster \
    ParameterKey=DesiredNodeCapacity,ParameterValue=2 \
    ParameterKey=NodeInstanceType,ParameterValue=t3.medium \
  --capabilities CAPABILITY_IAM \
  --region ap-southeast-1
```

**Note**: Stack creation typically takes 15-20 minutes. You can monitor progress with:

```bash
# Check stack status
aws cloudformation describe-stacks \
  --stack-name jenkins-eks-stack \
  --region ap-southeast-1 \
  --query 'Stacks[0].[StackStatus,StackStatusReason]' \
  --output text

# Wait for stack completion
aws cloudformation wait stack-create-complete \
  --stack-name jenkins-eks-stack \
  --region ap-southeast-1
```

### Step 3: Configure kubectl

Once the stack is created, configure kubectl to access the cluster:

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --name jenkins-eks-cluster \
  --region ap-southeast-1

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

### Step 4: Install AWS EBS CSI Driver

The EBS CSI driver is required for persistent volumes:

```bash
# Apply EBS CSI driver
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.20"

# Verify installation
kubectl get pods -n kube-system | grep ebs-csi
```

### Step 5: Deploy Jenkins

```bash
# Apply Jenkins deployment manifest
kubectl apply -f jenkins-deployment.yaml

# Verify deployment
kubectl get pods -n jenkins
kubectl get svc -n jenkins
```

### Step 6: Access Jenkins

#### Get the LoadBalancer Endpoint

```bash
# Wait for LoadBalancer endpoint assignment (may take 2-3 minutes)
kubectl get svc -n jenkins

# Get the endpoint DNS name
JENKINS_URL=$(kubectl get svc jenkins -n jenkins \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Jenkins URL: http://$JENKINS_URL"
```

#### Retrieve Initial Admin Password

```bash
# Get the Jenkins pod name
POD_NAME=$(kubectl get pod -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}')

# Retrieve the initial admin password
kubectl exec -it $POD_NAME -n jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword
```

### Step 7: Complete Jenkins Setup

1. Open your browser and navigate to `http://<JENKINS_URL>`
2. Enter the initial admin password retrieved in Step 6
3. Follow the Jenkins setup wizard to:
   - Install suggested plugins
   - Create the first admin user
   - Configure Jenkins URL
   - Save and complete setup

## Automated Deployment

For a fully automated deployment, use the provided script:

```bash
# Make the script executable
chmod +x deploy-jenkins.sh

# Run the deployment script
./deploy-jenkins.sh
```

The script will:
1. Validate the CloudFormation template
2. Create the CloudFormation stack
3. Wait for stack completion
4. Configure kubectl
5. Verify cluster connectivity
6. Install AWS EBS CSI Driver
7. Deploy Jenkins
8. Retrieve the LoadBalancer endpoint
9. Display access information

## Monitoring and Management

### View Jenkins Logs

```bash
# Stream Jenkins logs
kubectl logs -f -n jenkins -l app=jenkins
```

### Port Forwarding (Alternative to LoadBalancer)

```bash
# Create a local port forward
kubectl port-forward -n jenkins svc/jenkins 8080:80

# Access Jenkins at http://localhost:8080
```

### Monitor Resource Usage

```bash
# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n jenkins
```

### Scale the Node Group

```bash
# Update desired node count
aws eks update-nodegroup-config \
  --cluster-name jenkins-eks-cluster \
  --nodegroup-name jenkins-node-group \
  --scaling-config minSize=1,maxSize=4,desiredSize=3 \
  --region ap-southeast-1
```

## Cleanup

To delete all resources and avoid unnecessary charges:

```bash
# Delete Jenkins deployment
kubectl delete namespace jenkins

# Delete the CloudFormation stack
aws cloudformation delete-stack \
  --stack-name jenkins-eks-stack \
  --region ap-southeast-1

# Wait for stack deletion
aws cloudformation wait stack-delete-complete \
  --stack-name jenkins-eks-stack \
  --region ap-southeast-1

# Verify stack deletion
aws cloudformation describe-stacks \
  --stack-name jenkins-eks-stack \
  --region ap-southeast-1 2>&1 | grep -i "does not exist" || echo "Stack deletion in progress"
```

## Troubleshooting

### Pods not starting

```bash
# Describe pod for error details
kubectl describe pod -n jenkins -l app=jenkins

# Check recent pod events
kubectl get events -n jenkins --sort-by='.lastTimestamp'
```

### LoadBalancer endpoint not appearing

```bash
# Check service status
kubectl describe svc jenkins -n jenkins

# Check for pending service issues
kubectl get svc -n jenkins -o wide
```

### Storage issues

```bash
# Check PVC status
kubectl get pvc -n jenkins

# Describe PVC for details
kubectl describe pvc jenkins-pvc -n jenkins

# Check available storage classes
kubectl get storageclass
```

### Node issues

```bash
# Check node status
kubectl describe nodes

# Check node logs
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*jenkins*" \
  --region ap-southeast-1
```

## Cost Considerations

- **EKS Cluster**: ~$0.10/hour
- **t3.medium EC2 Instances (2)**: ~$0.04/hour each
- **EBS Volume (20GB)**: ~$2/month
- **NAT Gateway (2)**: ~$45/month each (data processing charges apply)
- **LoadBalancer**: ~$0.025/hour

**Estimated Monthly Cost**: ~$100-150 USD (depending on usage)

To reduce costs:
- Use fewer nodes (minimum 1)
- Use smaller instance types (t3.small)
- Remove NAT gateways if not needed (use VPC endpoints instead)
- Use spot instances (not recommended for Jenkins)

## Security Best Practices

1. **Network Security**:
   - Restrict LoadBalancer access using security groups
   - Use VPC endpoints for private access
   - Implement network policies in Kubernetes

2. **Access Control**:
   - Enable RBAC in Jenkins
   - Use AWS IAM integration
   - Rotate access credentials regularly

3. **Data Protection**:
   - Enable EBS encryption
   - Use encrypted connections (HTTPS)
   - Enable VPC flow logs

4. **Monitoring**:
   - Enable CloudWatch logging
   - Set up CloudWatch alarms
   - Use AWS CloudTrail for audit logs

## Additional Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS Best Practices](https://docs.aws.amazon.com/general/latest/gr/security_iam_service-specific-permissions.html)

## Support

For issues or questions:
1. Check CloudFormation events for deployment errors
2. Review Kubernetes pod logs
3. Check AWS EKS documentation
4. Review Jenkins logs and configuration
