# Jenkins on AWS EKS Deployment Summary

## Overview
This document provides a comprehensive summary of the Jenkins deployment on AWS EKS in the ap-southeast-1 (Singapore) region.

**Deployment Date**: December 23, 2025  
**AWS Account**: 010382427026  
**IAM User**: huy_ng  
**Region**: ap-southeast-1 (Singapore)  
**Kubernetes Version**: 1.32.9-eks-ecaa3a6

---

## AWS Infrastructure

### CloudFormation Stack
- **Stack Name**: `jenkins-eks-stack-v2`
- **Status**: CREATE_COMPLETE
- **Template File**: `jenkins-eks-stack-v2.yaml`

### VPC Configuration
- **CIDR Block**: 10.0.0.0/16
- **Public Subnets**:
  - `10.0.1.0/24` (ap-southeast-1a)
  - `10.0.2.0/24` (ap-southeast-1b)
- **Private Subnets**:
  - `10.0.11.0/24` (ap-southeast-1a)
  - `10.0.12.0/24` (ap-southeast-1b)
- **Internet Gateway**: Attached to VPC
- **NAT Gateways**: 2 (one per public subnet)
- **Route Tables**: Separate for public and private subnets

### EKS Cluster
- **Cluster Name**: `jenkins-eks-cluster`
- **Endpoint**: `https://D72B6B486C8E4ADAD1B3F23E8F02116B.gr7.ap-southeast-1.eks.amazonaws.com`
- **Kubernetes Version**: 1.32
- **Subnets**: All 4 subnets (2 public + 2 private)
- **Endpoint Access**: Public

### Worker Nodes
- **Deployment Method**: Auto Scaling Group (AWS::AutoScaling::AutoScalingGroup)
  - Note: AWS::EKS::NodeGroup not available in ap-southeast-1
- **Instance Type**: t3.medium
- **Desired Capacity**: 2 nodes
- **Min/Max Size**: 1-3 nodes
- **AMI**: EKS Optimized Amazon Linux 2 for Kubernetes 1.32
  - AMI Parameter: `/aws/service/eks/optimized-ami/1.32/amazon-linux-2/recommended/image_id`
  - AMI ID: `ami-009403f2047ac61d8`
- **Container Runtime**: containerd 1.7.29
- **Active Nodes**:
  - `ip-10-0-11-132.ap-southeast-1.compute.internal` (i-01809af0b5baf8fa0)
  - `ip-10-0-12-126.ap-southeast-1.compute.internal` (i-05b77eba9e4bc3d81)

### Launch Template
- **Name**: `jenkins-eks-cluster-launch-template`
- **User Data**: Bootstrap script to join EKS cluster
- **Key Configuration**:
  ```bash
  /etc/eks/bootstrap.sh jenkins-eks-cluster
  ```
- **Tags**:
  - `Name: jenkins-eks-cluster-node`
  - `kubernetes.io/cluster/jenkins-eks-cluster: owned`

---

## IAM Roles and Policies

### EKS Cluster Role
- **Role Name**: `jenkins-eks-stack-v2-ClusterRole-xxxxx`
- **Service Principal**: `eks.amazonaws.com`
- **Managed Policies**:
  - `arn:aws:iam::aws:policy/AmazonEKSClusterPolicy`

### Worker Node Role
- **Role Name**: `jenkins-eks-stack-v2-WorkerNodeRole-1KkCjHciQVnL`
- **Service Principal**: `ec2.amazonaws.com`
- **Managed Policies**:
  - `arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy`
  - `arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly`
  - `arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy`
  - `arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy` (Added for EBS CSI driver)

### Instance Profile
- **Name**: `jenkins-eks-stack-v2-WorkerNodeInstanceProfile-xxxxx`
- **Attached Role**: WorkerNodeRole

---

## Security Groups

### Cluster Security Group
- **Name**: `jenkins-eks-cluster-sg`
- **Purpose**: EKS cluster control plane communication
- **Ingress Rules**:
  - Port 443 from worker nodes (HTTPS for Kubernetes API)

### Worker Node Security Group
- **Name**: `jenkins-eks-cluster-worker-sg`
- **Ingress Rules**:
  - All traffic from cluster security group
  - All traffic from other worker nodes (self-referencing)
  - Port 443 from anywhere (for LoadBalancer access)
  - All traffic from VPC CIDR (10.0.0.0/16)
- **Egress Rules**:
  - All traffic to anywhere (0.0.0.0/0)

---

## Kubernetes Configuration

### aws-auth ConfigMap
**Critical Component**: Required for worker node authentication

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::010382427026:role/jenkins-eks-stack-v2-WorkerNodeRole-1KkCjHciQVnL
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
```

**Status**: Created manually (not included in CloudFormation)

---

## EBS CSI Driver

### Addon Configuration
- **Addon Name**: `aws-ebs-csi-driver`
- **Version**: v1.54.0-eksbuild.1
- **Status**: Active
- **Installation Method**: AWS EKS Addon
  ```bash
  aws eks create-addon --cluster-name jenkins-eks-cluster \
    --addon-name aws-ebs-csi-driver --region ap-southeast-1
  ```

### IAM Permissions
- **Required Policy**: `AmazonEBSCSIDriverPolicy`
- **Attached To**: WorkerNodeRole
- **Permissions Granted**:
  - `ec2:CreateSnapshot`
  - `ec2:AttachVolume`
  - `ec2:DetachVolume`
  - `ec2:ModifyVolume`
  - `ec2:DescribeAvailabilityZones`
  - `ec2:DescribeInstances`
  - `ec2:DescribeSnapshots`
  - `ec2:DescribeTags`
  - `ec2:DescribeVolumes`
  - `ec2:DescribeVolumesModifications`

---

## Jenkins Deployment

### Namespace
- **Name**: `jenkins`

### Deployment Configuration
**File**: `jenkins-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
  namespace: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      serviceAccountName: jenkins
      containers:
      - name: jenkins
        image: jenkins/jenkins:latest
        ports:
        - containerPort: 8080
        - containerPort: 50000
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1024Mi
        volumeMounts:
        - name: jenkins-home
          mountPath: /var/jenkins_home
        livenessProbe:
          httpGet:
            path: /login
            port: 8080
          initialDelaySeconds: 90
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /login
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
      volumes:
      - name: jenkins-home
        persistentVolumeClaim:
          claimName: jenkins-pvc
```

**Important Notes**:
- Docker socket mount (`/var/run/docker.sock`) was removed due to containerd runtime
- Original manifest included Docker socket - patched via kubectl

### Service Account
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: jenkins
```

### Services

#### LoadBalancer Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: jenkins
  namespace: jenkins
spec:
  type: LoadBalancer
  ports:
  - name: http
    port: 80
    targetPort: 8080
    protocol: TCP
  - name: agent
    port: 50000
    targetPort: 50000
    protocol: TCP
  selector:
    app: jenkins
```

- **External Endpoint**: `a17df7b731d9c4298917964238fcf2d0-1407133303.ap-southeast-1.elb.amazonaws.com`
- **Access URL**: `http://a17df7b731d9c4298917964238fcf2d0-1407133303.ap-southeast-1.elb.amazonaws.com`

#### Agent Service (ClusterIP)
```yaml
apiVersion: v1
kind: Service
metadata:
  name: jenkins-agent
  namespace: jenkins
spec:
  type: ClusterIP
  ports:
  - port: 50000
    targetPort: 50000
  selector:
    app: jenkins
```

### Storage Configuration

#### StorageClass
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

#### PersistentVolumeClaim
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  namespace: jenkins
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ebs-sc
  resources:
    requests:
      storage: 20Gi
```

- **Status**: Bound
- **Volume**: `pvc-3d22eccd-468d-4ba6-bb94-313cd31072a6`
- **Capacity**: 20Gi
- **Volume Type**: EBS gp3
- **Encryption**: Enabled

### Horizontal Pod Autoscaler
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: jenkins-hpa
  namespace: jenkins
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: jenkins
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

---

## Current Deployment Status

### Active Resources

**Pods**:
```
NAME                       READY   STATUS    RESTARTS   AGE
jenkins-85c894676-64rhz    1/1     Running   0          [current]
```

**Services**:
```
NAME            TYPE           CLUSTER-IP      EXTERNAL-IP                                                                    PORT(S)
jenkins         LoadBalancer   172.20.38.124   a17df7b731d9c4298917964238fcf2d0-1407133303.ap-southeast-1.elb.amazonaws.com   80:30546/TCP,50000:30843/TCP
jenkins-agent   ClusterIP      172.20.2.30     <none>                                                                         50000/TCP
```

**PersistentVolumeClaim**:
```
NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
jenkins-pvc   Bound    pvc-3d22eccd-468d-4ba6-bb94-313cd31072a6   20Gi       RWO            ebs-sc
```

---

## Access Information

### Initial Admin Access
- **URL**: http://a17df7b731d9c4298917964238fcf2d0-1407133303.ap-southeast-1.elb.amazonaws.com
- **Initial Admin Password**: `31508b185c9b4b36bf369d60eaea6a3a`
- **Password Location**: `/var/jenkins_home/secrets/initialAdminPassword` (inside pod)

### Retrieve Password Command
```bash
kubectl exec -n jenkins $(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}') -- cat /var/jenkins_home/secrets/initialAdminPassword
```

---

## Deployment Issues Resolved

### Issue 1: Circular Dependency in Security Groups
**Problem**: CloudFormation validation error with circular dependency  
**Solution**: Refactored inline ingress rules to separate `AWS::EC2::SecurityGroupIngress` resources

### Issue 2: AWS::EKS::NodeGroup Not Available
**Problem**: `Unrecognized resource types: [AWS::EKS::NodeGroup]` in ap-southeast-1  
**Solution**: Used `AWS::AutoScaling::AutoScalingGroup` with `AWS::EC2::LaunchTemplate` instead

### Issue 3: Kubernetes Version Outdated
**Problem**: Initial template used Kubernetes 1.28 (deprecated)  
**Solution**: Updated to Kubernetes 1.32 (latest stable in region)

### Issue 4: Worker Nodes Not Registering
**Problem**: Nodes showing "InService" in ASG but not appearing in `kubectl get nodes`  
**Root Cause**: Missing `aws-auth` ConfigMap in kube-system namespace  
**Solution**: Created aws-auth ConfigMap with WorkerNodeRole ARN mapping  
**Resolution Time**: 75 seconds after ConfigMap creation

### Issue 5: PVC Unbound - Missing EBS CSI Driver
**Problem**: PVC stuck in "Pending" state, Jenkins pod couldn't schedule  
**Root Cause**: EBS CSI driver not installed on cluster  
**Solution**: Installed EBS CSI driver addon via AWS CLI  
```bash
aws eks create-addon --cluster-name jenkins-eks-cluster --addon-name aws-ebs-csi-driver
```

### Issue 6: CSI Driver Unauthorized
**Problem**: EBS CSI controller pods in CrashLoopBackOff  
**Root Cause**: WorkerNodeRole missing EC2 API permissions  
**Solution**: Attached `AmazonEBSCSIDriverPolicy` to WorkerNodeRole  
```bash
aws iam attach-role-policy --role-name jenkins-eks-stack-v2-WorkerNodeRole-1KkCjHciQVnL \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

### Issue 7: Jenkins Pod ContainerCreating Forever
**Problem**: Pod stuck in ContainerCreating, MountVolume.SetUp failed  
**Root Cause**: Manifest tried to mount Docker socket (`/var/run/docker.sock`) but EKS uses containerd  
**Solution**: Patched deployment to remove Docker socket volume mount  
```bash
kubectl patch deployment jenkins -n jenkins --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/volumeMounts/1"}]'

kubectl patch deployment jenkins -n jenkins --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/volumes/1"}]'
```

### Issue 8: Jenkins Showing Login Page Instead of Setup Wizard
**Problem**: Jenkins displayed username/password login instead of first-time setup wizard  
**Root Cause**: Previous failed pod initialization left data in PersistentVolume  
**Solution**: Deleted PVC to clear data, redeployed for fresh installation  
```bash
kubectl scale deployment jenkins -n jenkins --replicas=0
kubectl delete pvc jenkins-pvc -n jenkins
kubectl apply -f jenkins-deployment.yaml
kubectl scale deployment jenkins -n jenkins --replicas=1
```

---

## Cost Considerations

### Monthly Cost Estimates (ap-southeast-1)

| Resource | Quantity | Unit Cost | Monthly Cost |
|----------|----------|-----------|--------------|
| EKS Cluster | 1 | $0.10/hour | ~$73 |
| EC2 t3.medium | 2 | $0.0416/hour | ~$60 |
| NAT Gateway | 2 | $0.045/hour | ~$66 |
| EBS gp3 20GB | 1 | $0.08/GB-month | ~$1.60 |
| Load Balancer | 1 | $0.0225/hour + data | ~$17 |
| **Total** | | | **~$217.60/month** |

*Note: Costs exclude data transfer and additional EBS snapshots*

---

## Maintenance Commands

### View All Resources
```bash
kubectl get all -n jenkins
```

### Check Pod Logs
```bash
kubectl logs -n jenkins -l app=jenkins -f
```

### Describe Pod
```bash
kubectl describe pod -n jenkins -l app=jenkins
```

### Access Jenkins Shell
```bash
kubectl exec -it -n jenkins $(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}') -- /bin/bash
```

### Scale Jenkins
```bash
# Scale down
kubectl scale deployment jenkins -n jenkins --replicas=0

# Scale up
kubectl scale deployment jenkins -n jenkins --replicas=1
```

### Update Jenkins Image
```bash
kubectl set image deployment/jenkins -n jenkins jenkins=jenkins/jenkins:lts
```

### Check EBS CSI Driver Status
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
```

---

## Cleanup Instructions

### Delete Jenkins Resources
```bash
kubectl delete namespace jenkins
```

### Delete CloudFormation Stack
```bash
aws cloudformation delete-stack --stack-name jenkins-eks-stack-v2 --region ap-southeast-1
```

### Delete EBS CSI Driver Addon
```bash
aws eks delete-addon --cluster-name jenkins-eks-cluster --addon-name aws-ebs-csi-driver --region ap-southeast-1
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS Region: ap-southeast-1              │
│                                                             │
│  ┌────────────────────────────────────────────────────┐   │
│  │              VPC (10.0.0.0/16)                     │   │
│  │                                                     │   │
│  │  ┌─────────────────┐    ┌─────────────────┐       │   │
│  │  │ Public Subnet   │    │ Public Subnet   │       │   │
│  │  │ 10.0.1.0/24     │    │ 10.0.2.0/24     │       │   │
│  │  │ AZ-1a           │    │ AZ-1b           │       │   │
│  │  │                 │    │                 │       │   │
│  │  │ ┌─────────────┐ │    │ ┌─────────────┐ │       │   │
│  │  │ │ NAT Gateway │ │    │ │ NAT Gateway │ │       │   │
│  │  │ └─────────────┘ │    │ └─────────────┘ │       │   │
│  │  └────────┬────────┘    └────────┬────────┘       │   │
│  │           │                      │                 │   │
│  │  ┌────────┴───────┐    ┌────────┴────────┐        │   │
│  │  │ Private Subnet │    │ Private Subnet  │        │   │
│  │  │ 10.0.11.0/24   │    │ 10.0.12.0/24    │        │   │
│  │  │ AZ-1a          │    │ AZ-1b           │        │   │
│  │  │                │    │                 │        │   │
│  │  │ ┌────────────┐ │    │ ┌────────────┐  │        │   │
│  │  │ │ Worker     │ │    │ │ Worker     │  │        │   │
│  │  │ │ Node 1     │ │    │ │ Node 2     │  │        │   │
│  │  │ │ t3.medium  │ │    │ │ t3.medium  │  │        │   │
│  │  │ │            │ │    │ │            │  │        │   │
│  │  │ │ ┌────────┐ │ │    │ │            │  │        │   │
│  │  │ │ │Jenkins │ │ │    │ │            │  │        │   │
│  │  │ │ │  Pod   │ │ │    │ │            │  │        │   │
│  │  │ │ └────────┘ │ │    │ │            │  │        │   │
│  │  │ └────────────┘ │    │ └────────────┘  │        │   │
│  │  └────────────────┘    └─────────────────┘        │   │
│  │                                                     │   │
│  │  ┌─────────────────────────────────────────┐      │   │
│  │  │        EKS Control Plane                │      │   │
│  │  │     (Managed by AWS)                    │      │   │
│  │  │  Kubernetes v1.32.9-eks-ecaa3a6         │      │   │
│  │  └─────────────────────────────────────────┘      │   │
│  │                                                     │   │
│  │  ┌─────────────────────────────────────────┐      │   │
│  │  │        Application Load Balancer        │      │   │
│  │  │  a17df7b731d9c...elb.amazonaws.com     │      │   │
│  │  └─────────────────────────────────────────┘      │   │
│  └────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌────────────────────────────────────────────────────┐   │
│  │              EBS Volumes (gp3, 20GB)               │   │
│  │         Managed by EBS CSI Driver                  │   │
│  └────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Next Steps

1. **Access Jenkins**: Navigate to the LoadBalancer URL
2. **Complete Setup Wizard**: Enter the initial admin password
3. **Install Plugins**: Choose "Install suggested plugins" or select custom plugins
4. **Create Admin User**: Set up your permanent admin credentials
5. **Configure Jenkins**: Set Jenkins URL and other global settings
6. **Create Your First Job**: Start building CI/CD pipelines

---

## References

### Documentation Files
- `jenkins-eks-stack-v2.yaml` - CloudFormation template
- `jenkins-deployment.yaml` - Kubernetes manifests
- `deploy-jenkins.ps1` - PowerShell deployment script
- `deploy-jenkins-final.sh` - Bash deployment script
- `README.md` - Quick start guide
- `DEPLOYMENT_GUIDE.md` - Detailed deployment steps
- `KUBERNETES_UPDATE.md` - Version upgrade documentation
- `DEPLOYMENT_COMPLETE.md` - Deployment status and troubleshooting

### AWS Documentation
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/)
- [EBS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

### Jenkins Documentation
- [Jenkins on Kubernetes](https://www.jenkins.io/doc/book/installing/kubernetes/)
- [Jenkins User Documentation](https://www.jenkins.io/doc/)

---

**Document Version**: 1.0  
**Last Updated**: December 23, 2025  
**Status**: Production Deployment Active
