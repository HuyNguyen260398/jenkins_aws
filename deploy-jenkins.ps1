# Jenkins EKS Deployment Script (PowerShell)
# This script deploys Jenkins on AWS EKS in ap-southeast-1

$ErrorActionPreference = "Stop"

# Configuration
$REGION = "ap-southeast-1"
$STACK_NAME = "jenkins-eks-stack"
$CLUSTER_NAME = "jenkins-eks-cluster"
$KUBERNETES_VERSION = "1.28"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Jenkins EKS Deployment Script" -ForegroundColor Cyan
Write-Host "Region: $REGION" -ForegroundColor Cyan
Write-Host "Stack Name: $STACK_NAME" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Step 1: Validate CloudFormation template
Write-Host ""
Write-Host "Step 1: Validating CloudFormation template..." -ForegroundColor Yellow

try {
    aws cloudformation validate-template `
        --template-body file://jenkins-eks-stack.yaml `
        --region $REGION | Out-Null
    Write-Host "Template validation successful!" -ForegroundColor Green
} catch {
    Write-Host "Template validation failed: $_" -ForegroundColor Red
    exit 1
}

# Step 2: Create CloudFormation Stack
Write-Host ""
Write-Host "Step 2: Creating CloudFormation stack..." -ForegroundColor Yellow

try {
    aws cloudformation create-stack `
        --stack-name $STACK_NAME `
        --template-body file://jenkins-eks-stack.yaml `
        --parameters `
            ParameterKey=ClusterName,ParameterValue=$CLUSTER_NAME `
            ParameterKey=DesiredNodeCapacity,ParameterValue=2 `
            ParameterKey=NodeInstanceType,ParameterValue=t3.medium `
        --capabilities CAPABILITY_IAM `
        --region $REGION
    Write-Host "Stack creation initiated!" -ForegroundColor Green
} catch {
    Write-Host "Stack creation failed: $_" -ForegroundColor Red
    exit 1
}

# Step 3: Wait for stack creation
Write-Host ""
Write-Host "Step 3: Waiting for CloudFormation stack creation..." -ForegroundColor Yellow
Write-Host "This may take 15-20 minutes. Please be patient..." -ForegroundColor Yellow

try {
    aws cloudformation wait stack-create-complete `
        --stack-name $STACK_NAME `
        --region $REGION
    Write-Host "Stack created successfully!" -ForegroundColor Green
} catch {
    Write-Host "Stack creation wait failed: $_" -ForegroundColor Red
    exit 1
}

# Step 4: Get cluster endpoint
Write-Host ""
Write-Host "Step 4: Retrieving cluster information..." -ForegroundColor Yellow

try {
    $clusterInfo = aws eks describe-cluster `
        --name $CLUSTER_NAME `
        --region $REGION `
        --query 'cluster.[endpoint,name,status]' `
        --output text
    
    Write-Host "Cluster Info: $clusterInfo" -ForegroundColor Green
} catch {
    Write-Host "Failed to retrieve cluster info: $_" -ForegroundColor Red
    exit 1
}

# Step 5: Configure kubectl
Write-Host ""
Write-Host "Step 5: Configuring kubectl..." -ForegroundColor Yellow

try {
    aws eks update-kubeconfig `
        --name $CLUSTER_NAME `
        --region $REGION
    Write-Host "kubectl configured successfully!" -ForegroundColor Green
} catch {
    Write-Host "kubectl configuration failed: $_" -ForegroundColor Red
    exit 1
}

# Step 6: Verify cluster connectivity
Write-Host ""
Write-Host "Step 6: Verifying cluster connectivity..." -ForegroundColor Yellow

try {
    kubectl cluster-info
    Write-Host ""
    kubectl get nodes
    Write-Host "Cluster connectivity verified!" -ForegroundColor Green
} catch {
    Write-Host "Cluster connectivity verification failed: $_" -ForegroundColor Red
    exit 1
}

# Step 7: Install AWS EBS CSI Driver
Write-Host ""
Write-Host "Step 7: Installing AWS EBS CSI Driver..." -ForegroundColor Yellow

try {
    kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.20"
    Write-Host "EBS CSI Driver installation initiated!" -ForegroundColor Green
    
    Write-Host "Waiting for EBS CSI Driver to be ready..." -ForegroundColor Yellow
    
    $maxAttempts = 30
    $attempt = 0
    $ready = $false
    
    while ($attempt -lt $maxAttempts -and -not $ready) {
        $pods = kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver -o json | ConvertFrom-Json
        
        if ($pods.items.Count -gt 0) {
            $allReady = $true
            foreach ($pod in $pods.items) {
                if ($pod.status.conditions -eq $null -or -not ($pod.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })) {
                    $allReady = $false
                    break
                }
            }
            $ready = $allReady
        }
        
        if (-not $ready) {
            Write-Host "Still waiting... (attempt $($attempt + 1)/$maxAttempts)" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            $attempt++
        }
    }
    
    if ($ready) {
        Write-Host "EBS CSI Driver is ready!" -ForegroundColor Green
    } else {
        Write-Host "EBS CSI Driver readiness timeout. Continuing anyway..." -ForegroundColor Yellow
    }
} catch {
    Write-Host "EBS CSI Driver installation warning: $_" -ForegroundColor Yellow
}

# Step 8: Deploy Jenkins
Write-Host ""
Write-Host "Step 8: Deploying Jenkins..." -ForegroundColor Yellow

try {
    kubectl apply -f jenkins-deployment.yaml
    Write-Host "Jenkins deployment initiated!" -ForegroundColor Green
} catch {
    Write-Host "Jenkins deployment failed: $_" -ForegroundColor Red
    exit 1
}

# Step 9: Wait for Jenkins to be ready
Write-Host ""
Write-Host "Step 9: Waiting for Jenkins pod to be ready..." -ForegroundColor Yellow
Write-Host "This may take 2-3 minutes..." -ForegroundColor Yellow

$maxAttempts = 60
$attempt = 0
$ready = $false

while ($attempt -lt $maxAttempts -and -not $ready) {
    try {
        $pods = kubectl get pods -n jenkins -l app=jenkins -o json | ConvertFrom-Json
        
        if ($pods.items.Count -gt 0) {
            $pod = $pods.items[0]
            if ($pod.status.conditions -ne $null -and ($pod.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })) {
                $ready = $true
                Write-Host "Jenkins pod is ready!" -ForegroundColor Green
            }
        }
        
        if (-not $ready) {
            Write-Host "Waiting for Jenkins pod to be ready... (attempt $($attempt + 1)/$maxAttempts)" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            $attempt++
        }
    } catch {
        Write-Host "Checking pod status... (attempt $($attempt + 1)/$maxAttempts)" -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        $attempt++
    }
}

# Step 10: Get LoadBalancer endpoint
Write-Host ""
Write-Host "Step 10: Retrieving Jenkins LoadBalancer endpoint..." -ForegroundColor Yellow

$jenkinsUrl = $null
$maxAttempts = 30
$attempt = 0

while ($attempt -lt $maxAttempts -and -not $jenkinsUrl) {
    try {
        $service = kubectl get svc jenkins -n jenkins -o json | ConvertFrom-Json
        $jenkinsUrl = $service.status.loadBalancer.ingress[0].hostname
        
        if (-not $jenkinsUrl) {
            Write-Host "Waiting for LoadBalancer endpoint assignment... (attempt $($attempt + 1)/$maxAttempts)" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            $attempt++
        }
    } catch {
        Write-Host "Waiting for LoadBalancer endpoint assignment... (attempt $($attempt + 1)/$maxAttempts)" -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        $attempt++
    }
}

if ($jenkinsUrl) {
    Write-Host "Jenkins is available at: http://$jenkinsUrl" -ForegroundColor Green
} else {
    Write-Host "Warning: LoadBalancer endpoint not yet available. Please check later with:" -ForegroundColor Yellow
    Write-Host "  kubectl get svc jenkins -n jenkins" -ForegroundColor Yellow
}

# Step 11: Get initial admin password info
Write-Host ""
Write-Host "Step 11: Initial Admin Password Info" -ForegroundColor Yellow
Write-Host "Run the following command to get the initial admin password:" -ForegroundColor Cyan
Write-Host ""
Write-Host '  `$POD_NAME = kubectl get pod -n jenkins -l app=jenkins -o jsonpath="{.items[0].metadata.name}"' -ForegroundColor Gray
Write-Host '  kubectl exec -it `$POD_NAME -n jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword' -ForegroundColor Gray
Write-Host ""

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Region: $REGION" -ForegroundColor White
Write-Host "Cluster Name: $CLUSTER_NAME" -ForegroundColor White
Write-Host "Stack Name: $STACK_NAME" -ForegroundColor White

if ($jenkinsUrl) {
    Write-Host "Jenkins URL: http://$jenkinsUrl" -ForegroundColor Green
} else {
    Write-Host "Jenkins URL: Pending LoadBalancer endpoint assignment" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Wait for the LoadBalancer endpoint to be assigned (if not shown above)" -ForegroundColor White
Write-Host "2. Access Jenkins at: http://<JENKINS_URL>" -ForegroundColor White
Write-Host "3. Retrieve the initial admin password using the command above" -ForegroundColor White
Write-Host "4. Complete Jenkins setup wizard" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor Cyan
