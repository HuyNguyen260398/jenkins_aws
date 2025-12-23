# Jenkins on EKS Deployment Summary

## ✅ Infrastructure Deployment Complete

### CloudFormation Stack
- **Stack Name**: jenkins-eks-stack-v2
- **Region**: ap-southeast-1 (Singapore)
- **Status**: CREATE_COMPLETE
- **Kubernetes Version**: 1.32 (Latest stable)

### EKS Cluster
- **Cluster Name**: jenkins-eks-cluster
- **API Endpoint**: https://D72B6B486C8E4ADAD1B3F23E8F02116B.gr7.ap-southeast-1.eks.amazonaws.com
- **Endpoint Status**: Public Access Enabled

### VPC & Networking
- **VPC CIDR**: 10.0.0.0/16
- **Public Subnets**: 2 (10.0.1.0/24, 10.0.2.0/24)
- **Private Subnets**: 2 (10.0.11.0/24, 10.0.12.0/24)
- **NAT Gateways**: 2 (one per AZ)
- **Internet Gateway**: Configured

### Worker Nodes
- **Desired Capacity**: 2
- **Instance Type**: t3.medium
- **AMI**: EKS Optimized Amazon Linux 2 (Kubernetes 1.32)
- **Instances Running**:
  - i-01809af0b5baf8fa0 (10.0.11.132)
  - i-05b77eba9e4bc3d81 (10.0.12.126)
- **Status**: Both instances running and bootstrapped

### Security Configuration
- **EKS Security Group**: Ingress from 0.0.0.0/0 on ports 80 and 443
- **Worker Security Group**: Ingress from cluster and itself on all ports
- **Node Tags**: kubernetes.io/cluster/jenkins-eks-cluster=owned

## ✅ Jenkins Deployment Complete

### Kubernetes Resources Created
- **Namespace**: jenkins
- **Deployment**: jenkins (1 replica, pending scheduling)
- **Service**: LoadBalancer (Jenkins UI on port 80)
- **Service**: ClusterIP (Jenkins Agents on port 50000)
- **PersistentVolumeClaim**: 20GB EBS volume
- **Storage Class**: ebs-sc (EBS CSI)
- **Horizontal Pod Autoscaler**: 1-3 replicas (70% CPU, 80% Memory)

### Jenkins Access Points
- **LoadBalancer DNS**: a17df7b731d9c4298917964238fcf2d0-1407133303.ap-southeast-1.elb.amazonaws.com
- **Service Port**: 80 (HTTP) → 8080 (Jenkins)
- **Agent Port**: 50000 (JNLP)

## Current Status

### Worker Nodes Registration
- **Nodes in Kubernetes**: 0 of 2
- **EC2 Instances Status**: Both running (in-service)
- **Bootstrap Status**: Completed successfully on both instances
- **Expected Status**: Nodes should register within 5-10 minutes

### Jenkins Pod Status
- **Status**: Pending (waiting for node to schedule)
- **Pod Name**: jenkins-dddf594c5-mrkcr
- **Age**: ~20 minutes
- **Storage**: Waiting for node to bind PVC

## Next Steps

### Monitor Node Registration
```bash
# Check nodes
kubectl get nodes -o wide

# Check Jenkins pod
kubectl get pods -n jenkins -o wide

# Watch Jenkins deployment
kubectl rollout status deployment/jenkins -n jenkins
```

### Access Jenkins
Once nodes register and pod starts (2-5 minutes):
```bash
# Get LoadBalancer endpoint
kubectl get svc jenkins -n jenkins

# Access at: http://<LOADBALANCER_DNS>
```

### Initial Configuration
```bash
# Get initial admin password
kubectl exec -n jenkins <POD_NAME> -- cat /var/jenkins_home/secrets/initialAdminPassword
```

## Infrastructure Costs

### Estimated Monthly Cost
- **EKS Cluster**: $0.10/hour = ~$73/month
- **EC2 Instances (2x t3.medium)**: $0.0416/hour each = ~$61/month
- **NAT Gateways (2x)**: $0.045/hour each = ~$66/month
- **EBS Storage (20GB)**: ~$2/month
- **LoadBalancer**: ~$17/month
- **Total**: ~$219/month

## Cleanup Commands

To remove all resources:
```bash
# Delete Jenkins namespace (removes all Kubernetes resources)
kubectl delete namespace jenkins

# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name jenkins-eks-stack-v2 --region ap-southeast-1

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name jenkins-eks-stack-v2 --region ap-southeast-1
```

## Troubleshooting

### Nodes Not Registering
If nodes don't register after 15 minutes:
1. Check EC2 instance system logs
2. Verify security group rules allow 443 from workers to cluster
3. Check kubelet logs: `/var/log/aws-routed-eni/ipamd.log`

### Jenkins Pod Not Starting
If pod remains pending after nodes register:
1. Check pod events: `kubectl describe pod -n jenkins <POD_NAME>`
2. Check storage: `kubectl get pvc -n jenkins`
3. Check node resources: `kubectl describe node <NODE_NAME>`

### LoadBalancer Not Getting IP
If LoadBalancer endpoint not assigned:
1. AWS Network Load Balancer might need 2-3 minutes to fully provision
2. Check service status: `kubectl get svc jenkins -n jenkins -w`
