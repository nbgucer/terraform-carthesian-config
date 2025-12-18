<#
.SYNOPSIS
    Build, push, and deploy Multi-Config App to AKS
.DESCRIPTION
    This script builds the Docker image, pushes it to ACR, and deploys to specified environment using Terraform
.PARAMETER Environment
    Target environment (dev, acc, prd, or all)
.PARAMETER ImageTag
    Docker image tag (default: latest)
.PARAMETER SkipBuild
    Skip Docker build step
.PARAMETER SkipPush
    Skip Docker push step
.PARAMETER SkipDeploy
    Skip Terraform deployment step
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "acc", "prd", "all")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$ImageTag = "latest",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBuild,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPush,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipDeploy
)

# Script configuration
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$TerraformDir = Join-Path $RootDir "terraform"
$SrcDir = Join-Path $RootDir "src\MultiConfigApp"

# Colors for output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Step {
    param([string]$Message)
    Write-ColorOutput "`n=== $Message ===" "Cyan"
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "✓ $Message" "Green"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "✗ $Message" "Red"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "ℹ $Message" "Yellow"
}

# Validate prerequisites
function Test-Prerequisites {
    Write-Step "Checking Prerequisites"
    
    $prerequisites = @(
        @{Name="Docker"; Command="docker --version"},
        @{Name="Azure CLI"; Command="az --version"},
        @{Name="Terraform"; Command="terraform --version"},
        @{Name="kubectl"; Command="kubectl version --client"}
    )
    
    $allPresent = $true
    foreach ($prereq in $prerequisites) {
        try {
            Invoke-Expression $prereq.Command | Out-Null
            Write-Success "$($prereq.Name) is installed"
        }
        catch {
            Write-Error "$($prereq.Name) is not installed or not in PATH"
            $allPresent = $false
        }
    }
    
    if (-not $allPresent) {
        throw "Missing prerequisites. Please install all required tools."
    }
}

# Read Terraform variables
function Get-TerraformVariables {
    Write-Step "Reading Terraform Configuration"
    
    $tfvarsFile = Join-Path $TerraformDir "terraform.tfvars"
    if (-not (Test-Path $tfvarsFile)) {
        throw "terraform.tfvars not found at $tfvarsFile"
    }
    
    $tfvars = @{}
    Get-Content $tfvarsFile | ForEach-Object {
        if ($_ -match '^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*"([^"]*)"') {
            $tfvars[$matches[1]] = $matches[2]
        }
    }
    
    return $tfvars
}

# Build Docker image
function Build-DockerImage {
    param(
        [string]$ImageName,
        [string]$Tag
    )
    
    Write-Step "Building Docker Image"
    Write-Info "Image: ${ImageName}:${Tag}"
    
    Push-Location $SrcDir
    try {
        docker build -t "${ImageName}:${Tag}" -f Dockerfile .
        if ($LASTEXITCODE -ne 0) {
            throw "Docker build failed"
        }
        Write-Success "Docker image built successfully"
    }
    finally {
        Pop-Location
    }
}

# Login to ACR and push image
function Push-DockerImageToACR {
    param(
        [string]$ACRName,
        [string]$ImageName,
        [string]$Tag
    )
    
    Write-Step "Pushing Image to Azure Container Registry"
    
    # Login to ACR
    # Write-Info "Logging in to ACR: $ACRName"
    # az acr login --name $ACRName
    # if ($LASTEXITCODE -ne 0) {
    #     throw "ACR login failed"
    # }
    
    # Get ACR login server
    $loginServer = az acr show --name $ACRName --query loginServer --output tsv
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get ACR login server"
    }
    
    Write-Info "ACR Login Server: $loginServer"
    
    # Tag image for ACR
    $acrImage = "${loginServer}/${ImageName}:${Tag}"
    Write-Info "Tagging image: $acrImage"
    docker tag "${ImageName}:${Tag}" $acrImage
    if ($LASTEXITCODE -ne 0) {
        throw "Docker tag failed"
    }
    
    # Push image
    Write-Info "Pushing image to ACR..."
    docker push $acrImage
    if ($LASTEXITCODE -ne 0) {
        throw "Docker push failed"
    }
    
    Write-Success "Image pushed successfully to ACR"
    return $loginServer
}

# Deploy with Terraform
function Deploy-WithTerraform {
    param(
        [string]$ImageTag
    )
    
    Write-Step "Deploying with Terraform"
    
    Push-Location $TerraformDir
    try {
        # Initialize Terraform
        Write-Info "Initializing Terraform..."
        terraform init
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform init failed"
        }
        
        # Validate configuration
        Write-Info "Validating Terraform configuration..."
        terraform validate
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform validation failed"
        }
        
        # Plan deployment
        Write-Info "Planning Terraform deployment..."
        terraform plan -var="docker_image_tag=$ImageTag" -out=tfplan
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform plan failed"
        }
        
        # Apply deployment
        Write-Info "Applying Terraform deployment..."
        terraform apply -auto-approve tfplan
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform apply failed"
        }
        
        Write-Success "Terraform deployment completed successfully"
        
        # Show outputs
        Write-Step "Deployment Outputs"
        terraform output -json | ConvertFrom-Json | ConvertTo-Json -Depth 10
    }
    finally {
        Pop-Location
    }
}

# Get AKS credentials
function Get-AKSCredentials {
    param(
        [string]$ClusterName,
        [string]$ResourceGroup
    )
    
    Write-Step "Getting AKS Credentials"
    Write-Info "Cluster: $ClusterName"
    Write-Info "Resource Group: $ResourceGroup"
    
    az aks get-credentials --name $ClusterName --resource-group $ResourceGroup --overwrite-existing
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get AKS credentials"
    }
    
    Write-Success "AKS credentials configured"
}

# Verify deployment
function Test-Deployment {
    param(
        [string]$Environment
    )
    
    Write-Step "Verifying Deployment"
    
    $namespaces = @("dev", "acc", "prd")
    if ($Environment -ne "all") {
        $namespaces = @($Environment)
    }
    
    foreach ($ns in $namespaces) {
        Write-Info "`nChecking namespace: $ns"
        
        # Check pods
        Write-Host "`nPods in $ns namespace:"
        kubectl get pods -n $ns
        
        # Check services
        Write-Host "`nServices in $ns namespace:"
        kubectl get services -n $ns
        
        # Check deployments
        Write-Host "`nDeployments in $ns namespace:"
        kubectl get deployments -n $ns
    }
}

# Main execution
try {
    Write-ColorOutput @"
╔═══════════════════════════════════════════════════════════╗
║     Multi-Config App Deployment Script                    ║
║     Environment: $Environment                             ║
║     Image Tag: $ImageTag                                  ║
╚═══════════════════════════════════════════════════════════╝
"@ "Magenta"

    # Check prerequisites
    #Test-Prerequisites
    
    # Read Terraform variables
    $tfVars = Get-TerraformVariables
    $acrName = $tfVars["acr_name"]
    $imageName = $tfVars["docker_image_name"]
    $aksCluster = $tfVars["aks_cluster_name"]
    $aksResourceGroup = $tfVars["aks_resource_group_name"]
    
    Write-Info "ACR Name: $acrName"
    Write-Info "Image Name: $imageName"
    Write-Info "AKS Cluster: $aksCluster"
    
    # Build Docker image
    if (-not $SkipBuild) {
        Build-DockerImage -ImageName $imageName -Tag $ImageTag
    } else {
        Write-Info "Skipping Docker build (SkipBuild flag set)"
    }
    
    # Push to ACR
    if (-not $SkipPush) {
        $loginServer = Push-DockerImageToACR -ACRName $acrName -ImageName $imageName -Tag $ImageTag
    } else {
        Write-Info "Skipping Docker push (SkipPush flag set)"
    }
    
    # Get AKS credentials
    Get-AKSCredentials -ClusterName $aksCluster -ResourceGroup $aksResourceGroup
    
    # Deploy with Terraform
    if (-not $SkipDeploy) {
        Deploy-WithTerraform -ImageTag $ImageTag
    } else {
        Write-Info "Skipping Terraform deployment (SkipDeploy flag set)"
    }
    
    # Verify deployment
    Test-Deployment -Environment $Environment
    
    Write-Step "Deployment Complete!"
    Write-Success "All applications deployed successfully to $Environment environment(s)"
    
    Write-ColorOutput @"

Next Steps:
1. Verify pods are running: kubectl get pods -n $Environment
2. Check logs: kubectl logs -n $Environment <pod-name>
3. Test the API: kubectl port-forward -n $Environment svc/<service-name> 8080:80
4. Access Swagger UI: http://localhost:8080/swagger

"@ "Green"

}
catch {
    Write-Error "Deployment failed: $_"
    Write-Host $_.ScriptStackTrace
    exit 1
}