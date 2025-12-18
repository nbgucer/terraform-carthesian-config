# Multi-Config App - AKS Deployment with Terraform

This project demonstrates deploying a single Docker image to multiple Kubernetes deployments with different configurations using Terraform and Azure Kubernetes Service (AKS).

## Architecture

- **Single Docker Image**: One .NET 8 application image
- **Multiple Deployments**: 2 applications (email-processor, sms-processor) × 3 environments (dev, acc, prd) = 6 deployments
- **Configuration-Based DI**: Different service implementations injected based on configuration
- **Environment Variables**: Configuration passed via Kubernetes environment variables

## Prerequisites

- Windows PC
- .NET 8 SDK
- Docker Desktop
- Azure CLI
- Terraform
- kubectl
- PowerShell 5.1 or PowerShell Core 7+
- Existing AKS cluster and ACR

## Project Structure


terraform-aks-deployment/
├── terraform/              # Terraform configuration files
│   ├── main.tf            # Main Terraform configuration
│   ├── variables.tf       # Variable definitions
│   ├── terraform.tfvars   # Variable values (update with your values)
│   └── outputs.tf         # Output definitions
├── src/
│   └── MultiConfigApp/    # .NET 8 Web API application
├── scripts/
│   └── deploy.ps1         # PowerShell deployment script
└── README.md

Configuration
1. Update Terraform Variables
Edit terraform/terraform.tfvars with your Azure resource details:


```terraform
aks_cluster_name        = "your-aks-cluster-name"
aks_resource_group_name = "your-aks-resource-group"
acr_name                = "yourACRname"
acr_resource_group_name = "your-acr-resource-group"
```

2. Application Configuration
The application configuration is defined in terraform/main.tf under the locals block:


```terraform
applications = {
  email-processor = {
    service_type        = "Email"
    app_display_name    = "Email Processor"
    feature_flag_alpha  = true
    # ... more config
  }
  sms-processor = {
    service_type        = "Sms"
    app_display_name    = "SMS Processor"
    # ... more config
  }
}
```

## Deployment
### Quick Start
#### Deploy to dev environment:


```bash
.\scripts\deploy.ps1 -Environment dev
```

#### Deploy to all environments:

```bash
.\scripts\deploy.ps1 -Environment all
```

### Deployment Options
#### Deploy with custom image tag:


```bash
.\scripts\deploy.ps1 -Environment dev -ImageTag "v1.0.0"
```
#### Skip Docker build (use existing image):


```bash
.\scripts\deploy.ps1 -Environment dev -SkipBuild
```
#### Skip Docker push (for testing Terraform changes):


```bash
.\scripts\deploy.ps1 -Environment dev -SkipBuild -SkipPush
```
#### Only run Terraform (skip Docker operations):


```bash
.\scripts\deploy.ps1 -Environment dev -SkipBuild -SkipPush
```

### Testing the Deployment
1. Check Pod Status

```bash
kubectl get pods -n dev
kubectl get pods -n acc
kubectl get pods -n prd
```
2. View Logs

```bash
kubectl logs -n dev -l app=email-processor
kubectl logs -n dev -l app=sms-processor
```
3. Port Forward and Test
Forward email-processor in dev:


```bash
kubectl port-forward -n dev svc/email-processor 8080:80
```
Forward sms-processor in dev:


```bash
kubectl port-forward -n dev svc/sms-processor 8081:80
```
4. Test API Endpoints
Open browser or use curl:

Get configuration info:

```bash
curl http://localhost:8080/api/config/info
```
Get feature flags:


```bash
curl http://localhost:8080/api/config/features
```
Send message:


```bash
curl -X POST http://localhost:8080/api/config/send -H "Content-Type: application/json" -d "{\"recipient\":\"test@example.com\",\"message\":\"Hello World\"}"
```
Swagger UI:


```bash
Start-Process "http://localhost:8080/swagger"
```

### How It Works
1. Configuration Injection
The application uses ASP.NET Core's configuration system to inject values:

appsettings.json: Default configuration
Environment Variables: Override configuration (Kubernetes env vars)
IOptions Pattern: Strongly-typed configuration access
2. Service Selection via DI
Based on the ServiceType configuration, different implementations are registered:



switch (appConfig.ServiceType?.ToLower())
{
    case "email":
        builder.Services.AddSingleton<IMessageService, EmailMessageService>();
        break;
    case "sms":
        builder.Services.AddSingleton<IMessageService, SmsMessageService>();
        break;
}
3. Terraform Configuration Matrix
Terraform creates all combinations of apps and environments:


```terraform
app_env_combinations = merge([
  for env_key, env_config in local.environments : {
    for app_key, app_config in local.applications :
    "${app_key}-${env_key}" => { ... }
  }
]...)
```

### Adding New Applications
To add a new application configuration:

- Edit terraform/main.tf
- Add new entry to local.applications:
Example:


```terraform
applications = {
  # ... existing apps
  push-notification = {
    service_type        = "Push"
    app_display_name    = "Push Notification Service"
    feature_flag_alpha  = false
    feature_flag_beta   = true
    api_timeout_seconds = 45
    max_retry_count     = 4
  }
}
```

3. Create new service implementation in C# (if needed) 4. Run deployment script

#### Adding New Environments
To add a new environment:

Edit terraform/main.tf
Add new entry to local.environments:
Example:


```terraform
environments = {
  # ... existing environments
  staging = {
    namespace = "staging"
    replicas  = 2
  }
}
```

4. Run deployment script


### CI/CD Integration
The deploy.ps1 script can be integrated into your CI/CD pipeline:

Azure DevOps Example

```yaml
- task: PowerShell@2
  inputs:
    filePath: 'scripts/deploy.ps1'
    arguments: '-Environment $(Environment) -ImageTag $(Build.BuildId)'
```

### Environment-Specific Overrides
You can override any configuration per environment in the terraform/main.tf locals block:


```terraform
app_env_combinations = merge([
  for env_key, env_config in local.environments : {
    for app_key, app_config in local.applications :
    "${app_key}-${env_key}" => {
      # Override for production
      feature_flag_alpha = env_key == "prd" ? true : app_config.feature_flag_alpha
    }
  }
]...)
``` 

## Quick Reference Commands
### Deployment

```bash
#### Full deployment to dev
.\scripts\deploy.ps1 -Environment dev

#### Deploy specific version to production
.\scripts\deploy.ps1 -Environment prd -ImageTag "v1.2.3"

#### Update only Terraform (no Docker build/push)
.\scripts\deploy.ps1 -Environment dev -SkipBuild -SkipPush
Kubernetes Operations


#### Get all resources in namespace
kubectl get all -n dev

#### Describe deployment
kubectl describe deployment -n dev email-processor

#### Scale deployment
kubectl scale deployment -n dev email-processor --replicas=3

#### Restart deployment
kubectl rollout restart deployment -n dev email-processor

#### Check rollout status
kubectl rollout status deployment -n dev email-processor
Debugging


#### Execute command in pod
kubectl exec -it -n dev <pod-name> -- /bin/bash

#### Port forward for local testing
kubectl port-forward -n dev svc/email-processor 8080:80

#### View events
kubectl get events -n dev --sort-by='.lastTimestamp'
Terraform Operations


#### Initialize Terraform
cd terraform
terraform init

#### Plan changes
terraform plan

#### Apply changes
terraform apply

#### Show current state
terraform show

#### List resources
terraform state list

#### Destroy all resources
terraform destroy
```