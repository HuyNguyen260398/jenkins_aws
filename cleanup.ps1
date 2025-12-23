# Jenkins EKS Cleanup Script (PowerShell)
# This script removes all Jenkins and EKS resources

$ErrorActionPreference = "Stop"

# Configuration
$REGION = "ap-southeast-1"
$STACK_NAME = "jenkins-eks-stack"
$CLUSTER_NAME = "jenkins-eks-cluster"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Jenkins EKS Cleanup Script" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "WARNING: This will delete all Jenkins and EKS resources!" -ForegroundColor Red
Write-Host "Region: $REGION" -ForegroundColor Yellow
Write-Host "Stack Name: $STACK_NAME" -ForegroundColor Yellow
Write-Host ""

# Confirmation
$confirmation = Read-Host "Are you sure you want to proceed? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Cleanup cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Step 1: Deleting Jenkins namespace..." -ForegroundColor Yellow

try {
    kubectl delete namespace jenkins --ignore-not-found=true
    Write-Host "Jenkins namespace deleted (or not found)" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not delete Jenkins namespace: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 2: Deleting AWS EBS CSI Driver..." -ForegroundColor Yellow

try {
    kubectl delete -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.20" --ignore-not-found=true
    Write-Host "EBS CSI Driver deleted (or not found)" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not delete EBS CSI Driver: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 3: Deleting CloudFormation stack..." -ForegroundColor Yellow
Write-Host "This may take 10-15 minutes..." -ForegroundColor Yellow

try {
    aws cloudformation delete-stack `
        --stack-name $STACK_NAME `
        --region $REGION
    Write-Host "Stack deletion initiated!" -ForegroundColor Green
} catch {
    Write-Host "Error deleting stack: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 4: Waiting for stack deletion..." -ForegroundColor Yellow

try {
    aws cloudformation wait stack-delete-complete `
        --stack-name $STACK_NAME `
        --region $REGION
    Write-Host "Stack deleted successfully!" -ForegroundColor Green
} catch {
    Write-Host "Stack deletion wait failed. Stack may still be deleting..." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 5: Verifying cleanup..." -ForegroundColor Yellow

try {
    $stacks = aws cloudformation describe-stacks `
        --stack-name $STACK_NAME `
        --region $REGION 2>&1
    
    Write-Host "Stack still exists. Please wait and check later." -ForegroundColor Yellow
} catch {
    if ($_ -like "*does not exist*") {
        Write-Host "Stack successfully deleted!" -ForegroundColor Green
    } else {
        Write-Host "Error checking stack status: $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Cleanup Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "The following resources have been marked for deletion:" -ForegroundColor White
Write-Host "✓ Jenkins namespace" -ForegroundColor Green
Write-Host "✓ EBS CSI Driver" -ForegroundColor Green
Write-Host "✓ CloudFormation Stack" -ForegroundColor Green
Write-Host ""
Write-Host "This includes:" -ForegroundColor White
Write-Host "  - EKS Cluster" -ForegroundColor White
Write-Host "  - Node Group" -ForegroundColor White
Write-Host "  - VPC and Subnets" -ForegroundColor White
Write-Host "  - Internet Gateway and NAT Gateways" -ForegroundColor White
Write-Host "  - Security Groups" -ForegroundColor White
Write-Host "  - IAM Roles" -ForegroundColor White
Write-Host "  - EBS Volumes" -ForegroundColor White
Write-Host ""
Write-Host "Important Notes:" -ForegroundColor Yellow
Write-Host "  - Deletion may take 10-15 minutes to complete" -ForegroundColor White
Write-Host "  - Some resources (like Elastic IPs) may need manual cleanup" -ForegroundColor White
Write-Host "  - Check CloudFormation console for detailed status" -ForegroundColor White
Write-Host ""
Write-Host "To verify all resources are deleted:" -ForegroundColor Yellow
Write-Host "  aws ec2 describe-vpcs --region $REGION --filters 'Name=tag:Name,Values=jenkins-vpc'" -ForegroundColor Gray
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
