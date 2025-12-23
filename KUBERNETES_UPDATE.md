# Kubernetes Version Update - Jenkins EKS Stack

## Summary of Changes

Updated the CloudFormation template to use the **latest available Kubernetes version (1.32)** supported in the ap-southeast-1 region.

### Version History

| Component | Previous | Current | Status |
|-----------|----------|---------|--------|
| Kubernetes | 1.28 | 1.32 | ✅ Updated |
| EKS Optimized AMI | 1.28 | 1.32 | ✅ Updated |
| CloudFormation Template | jenkins-eks-stack.yaml | jenkins-eks-stack-v2.yaml | ✅ New |

### What Was Changed

1. **Kubernetes Cluster Version**: Updated from `1.28` to `1.32` in the EKS cluster resource
2. **EKS Optimized AMI**: Updated from `/aws/service/eks/optimized-ami/1.28/...` to `/aws/service/eks/optimized-ami/1.32/...`
3. **CloudFormation Stack**: Deleted old stack and deployed new stack with updated configuration

### Why Kubernetes 1.32?

- Kubernetes 1.28 reached end-of-life and is no longer receiving security updates
- Kubernetes 1.32 is the latest stable version available in ap-southeast-1 region
- 1.33 and 1.34 AMI images are not yet available in ap-southeast-1
- Kubernetes 1.32 is fully supported for all EKS features and add-ons in the region

### Deployment Details

**Stack Name**: jenkins-eks-stack
**Region**: ap-southeast-1 (Singapore)
**Cluster Name**: jenkins-eks-cluster
**Kubernetes Version**: 1.32
**Node Group**: 
- Instance Type: t3.medium
- Desired Capacity: 2 nodes
- Min Size: 1
- Max Size: 4

### Timeline

- **Previous**: Kubernetes 1.28 (deprecated)
- **Current**: Kubernetes 1.32 (latest stable in ap-southeast-1)

### Next Steps

After stack creation completes:

1. Configure kubectl: `aws eks update-kubeconfig --name jenkins-eks-cluster --region ap-southeast-1`
2. Deploy Jenkins: `kubectl apply -f jenkins-deployment.yaml`
3. Monitor pod status: `kubectl get pods -n jenkins`
4. Get Jenkins access: `kubectl get svc -n jenkins`

### Security Note

Kubernetes 1.32 includes important security updates and patches that were not available in 1.28:
- Enhanced RBAC controls
- Improved network policies
- Updated API security
- Better secret management

This upgrade ensures your Jenkins deployment runs on a secure, actively supported Kubernetes version.
