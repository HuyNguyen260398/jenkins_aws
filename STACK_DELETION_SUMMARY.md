# CloudFormation Stack Deletion Summary

**Date:** December 27, 2025  
**Stack Name:** jenkins-eks-stack-v2  
**Region:** ap-southeast-1  
**Status:** ✅ Successfully Deleted

---

## Deletion Timeline

### 1. Initial Deletion Attempt
- **Command:** `aws cloudformation delete-stack --stack-name jenkins-eks-cluster`
- **Result:** Failed - incorrect stack name used

### 2. Second Deletion Attempt
- **Command:** `aws cloudformation delete-stack --stack-name jenkins-eks-stack-v2`
- **Result:** ❌ DELETE_FAILED
- **Failure Reason:** Resources failed to delete: `[AttachGateway, PublicSubnet1]`

### 3. Root Cause Analysis
Investigated the deletion failure and identified blocking resources:

#### Failed Resources:
- **AttachGateway (AWS::EC2::VPCGatewayAttachment)**
  - Error: "Exceeded attempts to wait" (NotStabilized)
  
- **PublicSubnet1 (AWS::EC2::Subnet)**
  - Error: "The subnet 'subnet-06e7392223f47bd78' has dependencies and cannot be deleted"
  - Subnet ID: `subnet-06e7392223f47bd78`

#### Root Cause:
Kubernetes had created resources outside of CloudFormation that were blocking deletion:

1. **Classic Load Balancer**
   - Name: `a17df7b731d9c4298917964238fcf2d0`
   - DNS: `a17df7b731d9c4298917964238fcf2d0-1407133303.ap-southeast-1.elb.amazonaws.com`
   - Network Interface: `eni-0a866d369571b0789`
   - Status: `in-use` in PublicSubnet1

2. **Security Group**
   - ID: `sg-007644ddc03f547c0`
   - Name: `k8s-elb-a17df7b731d9c4298917964238fcf2d0`
   - Created by Kubernetes for the ELB

### 4. Manual Resource Cleanup

#### Step 1: Delete Kubernetes Load Balancer
```bash
aws elb delete-load-balancer --load-balancer-name a17df7b731d9c4298917964238fcf2d0 --region ap-southeast-1
```
✅ Successfully deleted

#### Step 2: Delete Kubernetes Security Group
```bash
aws ec2 delete-security-group --group-id sg-007644ddc03f547c0 --region ap-southeast-1
```
✅ Successfully deleted

### 5. Final Deletion Attempt
- **Command:** `aws cloudformation delete-stack --stack-name jenkins-eks-stack-v2`
- **Monitoring:** `aws cloudformation wait stack-delete-complete --stack-name jenkins-eks-stack-v2`
- **Result:** ✅ Successfully completed
- **Verification:** Stack no longer exists (ValidationError returned)

---

## Resources Deleted

### CloudFormation-Managed Resources

#### Compute & Containers
- ✅ EKS Cluster: `jenkins-eks-cluster`
- ✅ Auto Scaling Group: `jenkins-eks-cluster-node-asg`
- ✅ Launch Template for worker nodes
- ✅ EC2 Instances (worker nodes)

#### Networking
- ✅ VPC: `jenkins-vpc` (vpc-02c7fdfed5b54a481)
- ✅ Public Subnets (2):
  - `jenkins-public-subnet-1` (10.0.1.0/24 in ap-southeast-1a)
  - `jenkins-public-subnet-2` (10.0.2.0/24 in ap-southeast-1b)
- ✅ Private Subnets (2):
  - `jenkins-private-subnet-1` (10.0.11.0/24 in ap-southeast-1a)
  - `jenkins-private-subnet-2` (10.0.12.0/24 in ap-southeast-1b)
- ✅ Internet Gateway: `jenkins-igw`
- ✅ NAT Gateways (2):
  - `jenkins-nat-gateway-1`
  - `jenkins-nat-gateway-2`
- ✅ Elastic IPs (2):
  - `jenkins-nat-eip-1`
  - `jenkins-nat-eip-2`
- ✅ Route Tables (3):
  - `jenkins-public-rt`
  - `jenkins-private-rt-1`
  - `jenkins-private-rt-2`

#### Security
- ✅ EKS Security Group: `jenkins-eks-sg`
- ✅ Worker Security Group: `jenkins-worker-sg`
- ✅ LoadBalancer Security Group: `jenkins-lb-sg`

#### IAM
- ✅ EKS Cluster Role: `jenkins-eks-cluster-role`
- ✅ Worker Node Role: `jenkins-worker-node-role`
- ✅ Worker Node Instance Profile

### Kubernetes-Created Resources (Manual Deletion)
- ✅ Classic Load Balancer: `a17df7b731d9c4298917964238fcf2d0`
- ✅ Security Group: `k8s-elb-a17df7b731d9c4298917964238fcf2d0`

---

## Key Learnings

### Why Deletion Failed Initially

When using Kubernetes Services of type `LoadBalancer`, Kubernetes automatically creates AWS resources (ELBs, security groups) that are **not tracked by CloudFormation**. These resources must be manually deleted before the CloudFormation stack can be successfully removed.

### Best Practices for Future Deployments

1. **Before Deleting a Stack with EKS:**
   - Delete all Kubernetes Services of type `LoadBalancer`
   - Delete all PersistentVolumes that provision EBS volumes
   - Verify no ENIs are in use: `aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=<vpc-id>"`

2. **Use kubectl to Clean Up Kubernetes Resources:**
   ```bash
   kubectl delete svc --all -n <namespace>
   kubectl delete pvc --all -n <namespace>
   ```

3. **Check for Orphaned Resources:**
   ```bash
   # Check for load balancers
   aws elb describe-load-balancers --region <region>
   aws elbv2 describe-load-balancers --region <region>
   
   # Check for security groups
   aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>"
   ```

---

## Verification Commands

To verify complete deletion:

```bash
# Verify stack is deleted
aws cloudformation describe-stacks --stack-name jenkins-eks-stack-v2 --region ap-southeast-1
# Expected: ValidationError - Stack does not exist

# Verify VPC is deleted
aws ec2 describe-vpcs --vpc-ids vpc-02c7fdfed5b54a481 --region ap-southeast-1
# Expected: InvalidVpcID.NotFound

# List any remaining stacks
aws cloudformation list-stacks --region ap-southeast-1 --query "StackSummaries[?StackStatus!='DELETE_COMPLETE'].StackName"
```

---

## Cost Impact

All resources have been successfully deleted. No further AWS charges will be incurred from this stack.

**Deleted Cost-Incurring Resources:**
- EKS Cluster (hourly charge)
- EC2 Instances (t3.medium × 2)
- NAT Gateways (2 × hourly charge + data processing)
- Elastic IPs (2 × hourly charge when not attached)
- EBS Volumes (attached to EC2 instances)
- Data transfer charges (stopped)

---

## Summary

The CloudFormation stack deletion encountered initial failures due to Kubernetes-managed resources outside of CloudFormation's control. After manually removing the Classic Load Balancer and its associated security group, the stack deletion completed successfully. All AWS resources have been cleaned up, and no further charges will be incurred.
