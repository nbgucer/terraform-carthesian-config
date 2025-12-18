terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Data sources for existing infrastructure
data "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  resource_group_name = var.aks_resource_group_name
}

data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group_name
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# Local variables for app-environment matrix
locals {
  # Define your environments
  environments = {
    dev = {
      namespace = "dev"
      replicas  = 1
    }
    acc = {
      namespace = "acc"
      replicas  = 2
    }
    prd = {
      namespace = "prd"
      replicas  = 3
    }
  }

  # Define your applications with their specific configurations
  applications = {
    email-processor = {
      service_type        = "Email"
      app_display_name    = "Email Processor"
      feature_flag_alpha  = true
      feature_flag_beta   = false
      api_timeout_seconds = 30
      max_retry_count     = 3
    }
    sms-processor = {
      service_type        = "Sms"
      app_display_name    = "SMS Processor"
      feature_flag_alpha  = false
      feature_flag_beta   = true
      api_timeout_seconds = 60
      max_retry_count     = 5
    }
  }

  # Create a flat map of all app-environment combinations
  app_env_combinations = merge([
    for env_key, env_config in local.environments : {
      for app_key, app_config in local.applications :
      "${app_key}-${env_key}" => {
        app_name         = app_key
        env_name         = env_key
        namespace        = env_config.namespace
        replicas         = env_config.replicas
        service_type     = app_config.service_type
        app_display_name = app_config.app_display_name
        
        # Environment-specific overrides
        feature_flag_alpha = env_key == "prd" ? true : app_config.feature_flag_alpha
        feature_flag_beta  = env_key == "dev" ? true : app_config.feature_flag_beta
        
        api_timeout_seconds = app_config.api_timeout_seconds
        max_retry_count     = app_config.max_retry_count
        
        # Environment-specific settings
        log_level = env_key == "prd" ? "Warning" : (env_key == "acc" ? "Information" : "Debug")
      }
    }
  ]...)
}

# Create namespaces for each environment
resource "kubernetes_namespace" "env" {
  for_each = local.environments

  metadata {
    name = each.value.namespace
    labels = {
      environment = each.key
      managed-by  = "terraform"
    }
  }
}

# Create a secret for ACR credentials in each namespace
resource "kubernetes_secret" "acr" {
  for_each = local.environments

  metadata {
    name      = "acr-secret"
    namespace = kubernetes_namespace.env[each.key].metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${data.azurerm_container_registry.acr.login_server}" = {
          username = data.azurerm_container_registry.acr.admin_username
          password = data.azurerm_container_registry.acr.admin_password
          email    = "terraform@example.com"
          auth     = base64encode("${data.azurerm_container_registry.acr.admin_username}:${data.azurerm_container_registry.acr.admin_password}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.env]
}

# Create ConfigMap for each app-environment combination
resource "kubernetes_config_map" "app" {
  for_each = local.app_env_combinations

  metadata {
    name      = "${each.value.app_name}-config"
    namespace = each.value.namespace
    labels = {
      app         = each.value.app_name
      environment = each.value.env_name
      managed-by  = "terraform"
    }
  }

  data = {
    "appsettings.json" = jsonencode({
      Logging = {
        LogLevel = {
          Default   = each.value.log_level
          Microsoft = "Warning"
        }
      }
      AppConfiguration = {
        ServiceType       = each.value.service_type
        AppDisplayName    = each.value.app_display_name
        Environment       = each.value.env_name
        FeatureFlagAlpha  = tostring(each.value.feature_flag_alpha)
        FeatureFlagBeta   = tostring(each.value.feature_flag_beta)
        ApiTimeoutSeconds = tostring(each.value.api_timeout_seconds)
        MaxRetryCount     = tostring(each.value.max_retry_count)
      }
    })
  }

  depends_on = [kubernetes_namespace.env]
}

# Create Deployment for each app-environment combination
resource "kubernetes_deployment" "app" {
  for_each = local.app_env_combinations

  metadata {
    name      = each.value.app_name
    namespace = each.value.namespace
    labels = {
      app         = each.value.app_name
      environment = each.value.env_name
      managed-by  = "terraform"
    }
  }

  spec {
    replicas = each.value.replicas

    selector {
      match_labels = {
        app         = each.value.app_name
        environment = each.value.env_name
      }
    }

    template {
      metadata {
        labels = {
          app         = each.value.app_name
          environment = each.value.env_name
        }
      }

      spec {
        image_pull_secrets {
          name = "acr-secret"
        }

        container {
          name  = each.value.app_name
          image = "${data.azurerm_container_registry.acr.login_server}/${var.docker_image_name}:${var.docker_image_tag}"

          port {
            container_port = 8080
            protocol       = "TCP"
          }

          env {
            name  = "ASPNETCORE_ENVIRONMENT"
            value = each.value.env_name
          }

          env {
            name  = "ASPNETCORE_URLS"
            value = "http://+:8080"
          }

          env {
            name  = "AppConfiguration__ServiceType"
            value = each.value.service_type
          }

          env {
            name  = "AppConfiguration__AppDisplayName"
            value = each.value.app_display_name
          }

          env {
            name  = "AppConfiguration__Environment"
            value = each.value.env_name
          }

          env {
            name  = "AppConfiguration__FeatureFlagAlpha"
            value = tostring(each.value.feature_flag_alpha)
          }

          env {
            name  = "AppConfiguration__FeatureFlagBeta"
            value = tostring(each.value.feature_flag_beta)
          }

          env {
            name  = "AppConfiguration__ApiTimeoutSeconds"
            value = tostring(each.value.api_timeout_seconds)
          }

          env {
            name  = "AppConfiguration__MaxRetryCount"
            value = tostring(each.value.max_retry_count)
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.app[each.key].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map.app,
    kubernetes_secret.acr
  ]
}

# Create Service for each app-environment combination
resource "kubernetes_service" "app" {
  for_each = local.app_env_combinations

  metadata {
    name      = each.value.app_name
    namespace = each.value.namespace
    labels = {
      app         = each.value.app_name
      environment = each.value.env_name
      managed-by  = "terraform"
    }
  }

  spec {
    selector = {
      app         = each.value.app_name
      environment = each.value.env_name
    }

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.app]
}