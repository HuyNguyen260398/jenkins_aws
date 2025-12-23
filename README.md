# Jenkins Deployment on AWS EKS

This repository contains a complete CloudFormation stack and Kubernetes manifests to deploy Jenkins on AWS EKS (Elastic Kubernetes Service) in the `ap-southeast-1` region.

**Current Jenkins URL**: http://a17df7b731d9c4298917964238fcf2d0-1407133303.ap-southeast-1.elb.amazonaws.com

## Quick Start

### Prerequisites
- AWS CLI configured
- kubectl installed
- Appropriate IAM permissions

### One-Command Deployment (PowerShell - Windows)

```powershell
.\deploy-jenkins.ps1
```

### One-Command Deployment (Bash - Linux/Mac)

```bash
chmod +x deploy-jenkins.sh
./deploy-jenkins.sh
```

## What's Included

### Files

| File | Description |
|------|-------------|
| `jenkins-eks-stack-v2.yaml` | CloudFormation template for EKS infrastructure |
| `jenkins-deployment.yaml` | Kubernetes manifests for Jenkins deployment |
| `deploy-jenkins.sh` | Bash deployment script |
| `deploy-jenkins.ps1` | PowerShell deployment script |
| `DEPLOYMENT_GUIDE.md` | Comprehensive deployment guide |
| `README.md` | This file |

### Infrastructure Created

1. **VPC & Networking**
   - Custom VPC with 2 public and 2 private subnets
   - Internet Gateway and NAT Gateways
   - Route tables for public/private routing

2. **EKS Cluster**
   - Kubernetes 1.32
   - Auto-managed control plane
   - Health monitoring and auto-healing

3. **Worker Nodes**
   - 2 t3.medium instances (configurable)
   - Auto Scaling Group support
   - IAM roles with proper permissions

4. **Jenkins**
   - Jenkins latest image from official Docker Hub
   - 20GB persistent EBS storage
   - LoadBalancer service for public access
   - Horizontal Pod Autoscaler (1-3 replicas)

5. **Security**
   - Network Security Groups properly configured
   - IAM roles with least privilege
   - Secure communication between components

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS Region (ap-southeast-1)             │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐│
│  │                        VPC (10.0.0.0/16)               ││
│  │                                                        ││
│  │  ┌──────────────────────────────────────────────────┐ ││
│  │  │           Public Subnets (2 AZs)                 │ ││
│  │  │  ┌────────────────────────────────────────────┐  │ ││
│  │  │  │     Internet Gateway                       │  │ ││
│  │  │  │  NAT Gateways (for private subnet access) │  │ ││
│  │  │  └────────────────────────────────────────────┘  │ ││
│  │  └──────────────────────────────────────────────────┘ ││
│  │                                                        ││
│  │  ┌──────────────────────────────────────────────────┐ ││
│  │  │      EKS Cluster Control Plane (Managed)         │ ││
│  │  └──────────────────────────────────────────────────┘ ││
│  │                                                        ││
│  │  ┌──────────────────────────────────────────────────┐ ││
│  │  │        Private Subnets (2 AZs) - Nodes          │ ││
│  │  │  ┌────────────────────────────────────────────┐  │ ││
│  │  │  │  Node 1 (t3.medium)                        │  │ ││
│  │  │  │  ┌──────────────────────────────────────┐  │  │ ││
│  │  │  │  │   Jenkins Pod                        │  │  │ ││
│  │  │  │  │   ├─ HTTP (8080 → 80)               │  │  │ ││
│  │  │  │  │   └─ Agent (50000)                  │  │  │ ││
│  │  │  │  └──────────────────────────────────────┘  │  │ ││
│  │  │  └────────────────────────────────────────────┘  │ ││
│  │  │  ┌────────────────────────────────────────────┐  │ ││
│  │  │  │  Node 2 (t3.medium)                        │  │ ││
│  │  │  └────────────────────────────────────────────┘  │ ││
│  │  └──────────────────────────────────────────────────┘ ││
│  │                                                        ││
│  │  ┌──────────────────────────────────────────────────┐ ││
│  │  │  LoadBalancer Service                           │ ││
│  │  │  Endpoint: jenkins-*.region.elb.amazonaws.com   │ ││
│  │  │  http://<ENDPOINT> → Jenkins (8080)             │ ││
│  │  └──────────────────────────────────────────────────┘ ││
│  │                                                        ││
│  │  ┌──────────────────────────────────────────────────┐ ││
│  │  │  EBS Storage (20GB)                              │ ││
│  │  │  ├─ Jenkins Home (/var/jenkins_home)            │ ││
│  │  │  ├─ Builds & Artifacts                          │ ││
│  │  │  └─ Plugins & Configuration                     │ ││
│  │  └──────────────────────────────────────────────────┘ ││
│  └────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Deployment Steps

### Option 1: Automated Deployment (Recommended)

**For Windows (PowerShell):**
```powershell
cd c:\Workspace\jenkins_aws
.\deploy-jenkins.ps1
```

**For Linux/Mac (Bash):**
```bash
cd c:\Workspace\jenkins_aws
chmod +x deploy-jenkins.sh
./deploy-jenkins.sh
```

### Option 2: Manual Deployment

```bash
# 1. Validate template
aws cloudformation validate-template \
  --template-body file://jenkins-eks-stack-v2.yaml \
  --region ap-southeast-1

# 2. Create stack
aws cloudformation create-stack \
  --stack-name jenkins-eks-stack-v2 \
  --template-body file://jenkins-eks-stack-v2.yaml \
  --parameters \
    ParameterKey=ClusterName,ParameterValue=jenkins-eks-cluster \
    ParameterKey=DesiredNodeCapacity,ParameterValue=2 \
  --capabilities CAPABILITY_IAM \
  --region ap-southeast-1

# 3. Wait for completion (15-20 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name jenkins-eks-stack-v2 \
  --region ap-southeast-1

# 4. Configure kubectl
aws eks update-kubeconfig \
  --name jenkins-eks-cluster \
  --region ap-southeast-1

# 5. Install EBS CSI Driver (as addon)
aws eks create-addon --cluster-name jenkins-eks-cluster \
  --addon-name aws-ebs-csi-driver --region ap-southeast-1

# 6. Attach EBS CSI IAM policy to worker node role
ROLE_NAME=$(aws iam list-roles --query 'Roles[?contains(RoleName, `WorkerNodeRole`)].RoleName' --output text)
aws iam attach-role-policy --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

# 7. Deploy Jenkins
kubectl apply -f jenkins-deployment.yaml

# 8. Get LoadBalancer endpoint
kubectl get svc -n jenkins

# 9. Get initial admin password
POD_NAME=$(kubectl get pod -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD_NAME -n jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword
```

## Accessing Jenkins

Once deployed, Jenkins is accessible at:
```
http://a17df7b731d9c4298917964238fcf2d0-1407133303.ap-southeast-1.elb.amazonaws.com
```

### Finding the LoadBalancer Endpoint

```bash
# Check service status
kubectl get svc -n jenkins

# Get the DNS name
kubectl get svc jenkins -n jenkins \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Initial Setup

1. Open Jenkins URL in browser
2. Enter the initial admin password (see step 8 above)
3. Install suggested plugins
4. Create first admin user
5. Configure Jenkins URL and complete setup

## Configuration Options

### Customize Deployment

Edit the CloudFormation stack parameters:

```bash
aws cloudformation update-stack \
  --stack-name jenkins-eks-stack-v2 \
  --parameters \
    ParameterKey=DesiredNodeCapacity,ParameterValue=3 \
    ParameterKey=NodeInstanceType,ParameterValue=t3.large \
  --capabilities CAPABILITY_IAM \
  --region ap-southeast-1
```

### Available Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| ClusterName | jenkins-eks-cluster | EKS cluster name |
| NodeGroupName | jenkins-node-group | Node group name |
| DesiredNodeCapacity | 2 | Number of nodes |
| NodeInstanceType | t3.medium | EC2 instance type |
| VpcCIDR | 10.0.0.0/16 | VPC CIDR block |

## Monitoring

### Check Deployment Status

```bash
# View pods
kubectl get pods -n jenkins

# View services
kubectl get svc -n jenkins

# View nodes
kubectl get nodes

# Check events
kubectl get events -n jenkins
```

### View Logs

```bash
# Stream Jenkins logs
kubectl logs -f -n jenkins -l app=jenkins

# View specific pod logs
kubectl logs -n jenkins <POD_NAME>
```

### Monitor Resources

```bash
# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -n jenkins
```

## Cleanup

To remove all resources:

```bash
# Delete Jenkins namespace (removes all Jenkins resources)
kubectl delete namespace jenkins

# Delete CloudFormation stack
aws cloudformation delete-stack \
  --stack-name jenkins-eks-stack-v2 \
  --region ap-southeast-1

# Wait for deletion
aws cloudformation wait stack-delete-complete \
  --stack-name jenkins-eks-stack-v2 \
  --region ap-southeast-1
```

## Cost Estimation

| Resource | Cost |
|----------|------|
| EKS Cluster | $0.10/hour |
| t3.medium Instances (2) | $0.0832/hour |
| EBS Volume (20GB) | ~$2/month |
| NAT Gateways (2) | ~$90/month |
| LoadBalancer | $0.025/hour |
| **Estimated Monthly** | **~$100-150** |

## Troubleshooting

### Common Issues

1. **Pod not starting**
   ```bash
   kubectl describe pod -n jenkins -l app=jenkins
   ```

2. **LoadBalancer endpoint not appearing**
   ```bash
   kubectl describe svc jenkins -n jenkins
   ```

3. **Storage issues**
   ```bash
   kubectl get pvc -n jenkins
   kubectl describe pvc jenkins-pvc -n jenkins
   ```

4. **Node issues**
   ```bash
   kubectl describe nodes
   ```

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed troubleshooting.

## Security Considerations

- ✅ Network security groups properly configured
- ✅ IAM roles with least privilege permissions
- ✅ EBS volumes encrypted by default
- ✅ Private worker node subnets
- ⚠️ LoadBalancer exposes Jenkins publicly (use firewall rules or IP whitelist)
- ⚠️ Default Jenkins configuration - secure after setup

## Best Practices

1. **Change Jenkins Admin Password**: Immediately after setup
2. **Configure Plugins**: Install only required plugins
3. **Enable SSL/TLS**: Use HTTPS for external access
4. **Backup Configuration**: Regular Jenkins backups
5. **Monitor Resources**: Set up CloudWatch alarms
6. **Use IAM Roles**: For Jenkins to AWS service access
7. **Network Policies**: Restrict traffic between pods

## Documentation

- [JENKINS_DEPLOYMENT_SUMMARY.md](JENKINS_DEPLOYMENT_SUMMARY.md) - Complete deployment summary
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Comprehensive deployment guide
- [CloudFormation Template](jenkins-eks-stack-v2.yaml) - Infrastructure as code
- [Kubernetes Manifests](jenkins-deployment.yaml) - Jenkins deployment specs

## Support & Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS Best Practices](https://docs.aws.amazon.com/general/)

## License

This project is provided as-is for educational and deployment purposes.

## Author

Created for automated Jenkins deployment on AWS EKS

---

**Last Updated**: December 24, 2025  
**Region**: ap-southeast-1  
**EKS Version**: 1.32  
**Jenkins URL**: http://a17df7b731d9c4298917964238fcf2d0-1407133303.ap-southeast-1.elb.amazonaws.com
