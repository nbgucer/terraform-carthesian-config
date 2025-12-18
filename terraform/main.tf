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
  # ========================================
  # COMMON CONFIGURATION
  # ========================================
  # These settings apply to ALL applications unless overridden
  common_config = {
    # Resource limits
    cpu_request    = "100m"
    cpu_limit      = "500m"
    memory_request = "128Mi"
    memory_limit   = "512Mi"
    
    # Health check settings
    liveness_initial_delay  = 30
    liveness_period         = 10
    readiness_initial_delay = 10
    readiness_period        = 5
    
    # Application defaults
    api_timeout_seconds = 30
    max_retry_count     = 3
    feature_flag_alpha  = false
    feature_flag_beta   = false
    
    # Logging defaults
    log_level_dev = "Debug"
    log_level_acc = "Information"
    log_level_prd = "Warning"
    
    # Database connection settings (example)
    db_connection_timeout = 30
    db_max_pool_size      = 100
    db_min_pool_size      = 10
    
    # API settings (example)
    api_rate_limit_per_minute = 1000
    api_enable_cors           = true
    
    # Cache settings (example)
    cache_enabled            = true
    cache_expiration_minutes = 60
  }

  # ========================================
  # ENVIRONMENT-SPECIFIC COMMON CONFIGURATION
  # ========================================
  # These settings apply to ALL apps in a specific environment
  environment_common_config = {
    dev = {
      enable_swagger           = true
      enable_detailed_errors   = true
      enable_debug_logging     = true
      db_connection_timeout    = 60  # Override: longer timeout in dev
      api_rate_limit_per_minute = 10000  # Override: higher limit in dev
    }
    acc = {
      enable_swagger           = false
      enable_detailed_errors   = true
      enable_debug_logging     = false
      db_connection_timeout    = 30
      api_rate_limit_per_minute = 5000
    }
    prd = {
      enable_swagger           = false
      enable_detailed_errors   = false
      enable_debug_logging     = false
      db_connection_timeout    = 30
      api_rate_limit_per_minute = 1000
    }
  }

  # ========================================
  # ENVIRONMENTS
  # ========================================
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

  # ========================================
  # APPLICATIONS
  # ========================================
  # Define your applications with their SPECIFIC configurations
  # Common config is automatically merged, you only need to specify differences
  applications = {
    email-processor = {
      service_type       = "Email"
      app_display_name   = "Email Processor"
      
      # Override common config for this specific app
      api_timeout_seconds = 45  # Override: email needs more time
      max_retry_count     = 5   # Override: email needs more retries
      
      # App-specific configuration
      email_batch_size    = 100
      email_smtp_server   = "smtp.example.com"
      email_smtp_port     = 587
    }
    
    sms-processor = {
      service_type       = "Sms"
      app_display_name   = "SMS Processor"
      
      # Override common config for this specific app
      api_timeout_seconds = 20  # Override: SMS is faster
      max_retry_count     = 3   # Use common default
      
      # App-specific configuration
      sms_batch_size      = 50
      sms_provider        = "twilio"
      sms_max_length      = 160
    }
  }

  # ========================================
  # MERGE LOGIC
  # ========================================
  # Create a flat map of all app-environment combinations with merged configuration
  app_env_combinations = merge([
    for env_key, env_config in local.environments : {
      for app_key, app_config in local.applications :
      "${app_key}-${env_key}" => merge(
        # 1. Start with common config
        local.common_config,
        
        # 2. Merge environment-specific common config
        local.environment_common_config[env_key],
        
        # 3. Merge application-specific config
        app_config,
        
        # 4. Add computed/derived values
        {
          app_name    = app_key
          env_name    = env_key
          namespace   = env_config.namespace
          replicas    = env_config.replicas
          
          # Environment-specific overrides (business logic)
          feature_flag_alpha = env_key == "prd" ? true : lookup(app_config, "feature_flag_alpha", local.common_config.feature_flag_alpha)
          feature_flag_beta  = env_key == "dev" ? true : lookup(app_config, "feature_flag_beta", local.common_config.feature_flag_beta)
          
          # Computed log level based on environment
          log_level = env_key == "prd" ? local.common_config.log_level_prd : (
            env_key == "acc" ? local.common_config.log_level_acc : local.common_config.log_level_dev
          )
          
          # Generate full app identifier
          full_app_name = "${app_key}-${env_key}"
        }
      )
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
        # Core app settings
        ServiceType      = each.value.service_type
        AppDisplayName   = each.value.app_display_name
        Environment      = each.value.env_name
        FullAppName      = each.value.full_app_name
        
        # Feature flags
        FeatureFlagAlpha = tostring(each.value.feature_flag_alpha)
        FeatureFlagBeta  = tostring(each.value.feature_flag_beta)
        
        # API settings
        ApiTimeoutSeconds      = tostring(each.value.api_timeout_seconds)
        MaxRetryCount          = tostring(each.value.max_retry_count)
        ApiRateLimitPerMinute  = tostring(each.value.api_rate_limit_per_minute)
        ApiEnableCors          = tostring(each.value.api_enable_cors)
        
        # Database settings
        DbConnectionTimeout = tostring(each.value.db_connection_timeout)
        DbMaxPoolSize       = tostring(each.value.db_max_pool_size)
        DbMinPoolSize       = tostring(each.value.db_min_pool_size)
        
        # Cache settings
        CacheEnabled           = tostring(each.value.cache_enabled)
        CacheExpirationMinutes = tostring(each.value.cache_expiration_minutes)
        
        # Debug settings
        EnableSwagger        = tostring(each.value.enable_swagger)
        EnableDetailedErrors = tostring(each.value.enable_detailed_errors)
        EnableDebugLogging   = tostring(each.value.enable_debug_logging)
        
        # App-specific settings (conditionally included)
        EmailBatchSize   = lookup(each.value, "email_batch_size", null) != null ? tostring(each.value.email_batch_size) : null
        EmailSmtpServer  = lookup(each.value, "email_smtp_server", null)
        EmailSmtpPort    = lookup(each.value, "email_smtp_port", null) != null ? tostring(each.value.email_smtp_port) : null
        
        SmsBatchSize     = lookup(each.value, "sms_batch_size", null) != null ? tostring(each.value.sms_batch_size) : null
        SmsProvider      = lookup(each.value, "sms_provider", null)
        SmsMaxLength     = lookup(each.value, "sms_max_length", null) != null ? tostring(each.value.sms_max_length) : null
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

          # Environment variables - all configuration passed here
          env {
            name  = "ASPNETCORE_ENVIRONMENT"
            value = each.value.env_name
          }

          env {
            name  = "ASPNETCORE_URLS"
            value = "http://+:8080"
          }

          # Core settings
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
            name  = "AppConfiguration__FullAppName"
            value = each.value.full_app_name
          }

          # Feature flags
          env {
            name  = "AppConfiguration__FeatureFlagAlpha"
            value = tostring(each.value.feature_flag_alpha)
          }

          env {
            name  = "AppConfiguration__FeatureFlagBeta"
            value = tostring(each.value.feature_flag_beta)
          }

          # API settings
          env {
            name  = "AppConfiguration__ApiTimeoutSeconds"
            value = tostring(each.value.api_timeout_seconds)
          }

          env {
            name  = "AppConfiguration__MaxRetryCount"
            value = tostring(each.value.max_retry_count)
          }

          env {
            name  = "AppConfiguration__ApiRateLimitPerMinute"
            value = tostring(each.value.api_rate_limit_per_minute)
          }

          env {
            name  = "AppConfiguration__ApiEnableCors"
            value = tostring(each.value.api_enable_cors)
          }

          # Database settings
          env {
            name  = "AppConfiguration__DbConnectionTimeout"
            value = tostring(each.value.db_connection_timeout)
          }

          env {
            name  = "AppConfiguration__DbMaxPoolSize"
            value = tostring(each.value.db_max_pool_size)
          }

          env {
            name  = "AppConfiguration__DbMinPoolSize"
            value = tostring(each.value.db_min_pool_size)
          }

          # Cache settings
          env {
            name  = "AppConfiguration__CacheEnabled"
            value = tostring(each.value.cache_enabled)
          }

          env {
            name  = "AppConfiguration__CacheExpirationMinutes"
            value = tostring(each.value.cache_expiration_minutes)
          }

          # Debug settings
          env {
            name  = "AppConfiguration__EnableSwagger"
            value = tostring(each.value.enable_swagger)
          }

          env {
            name  = "AppConfiguration__EnableDetailedErrors"
            value = tostring(each.value.enable_detailed_errors)
          }

          env {
            name  = "AppConfiguration__EnableDebugLogging"
            value = tostring(each.value.enable_debug_logging)
          }

          # App-specific settings (conditionally added)
          dynamic "env" {
            for_each = lookup(each.value, "email_batch_size", null) != null ? [1] : []
            content {
              name  = "AppConfiguration__EmailBatchSize"
              value = tostring(each.value.email_batch_size)
            }
          }

          dynamic "env" {
            for_each = lookup(each.value, "email_smtp_server", null) != null ? [1] : []
            content {
              name  = "AppConfiguration__EmailSmtpServer"
              value = each.value.email_smtp_server
            }
          }

          dynamic "env" {
            for_each = lookup(each.value, "email_smtp_port", null) != null ? [1] : []
            content {
              name  = "AppConfiguration__EmailSmtpPort"
              value = tostring(each.value.email_smtp_port)
            }
          }

          dynamic "env" {
            for_each = lookup(each.value, "sms_batch_size", null) != null ? [1] : []
            content {
              name  = "AppConfiguration__SmsBatchSize"
              value = tostring(each.value.sms_batch_size)
            }
          }

          dynamic "env" {
            for_each = lookup(each.value, "sms_provider", null) != null ? [1] : []
            content {
              name  = "AppConfiguration__SmsProvider"
              value = each.value.sms_provider
            }
          }

          dynamic "env" {
            for_each = lookup(each.value, "sms_max_length", null) != null ? [1] : []
            content {
              name  = "AppConfiguration__SmsMaxLength"
              value = tostring(each.value.sms_max_length)
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = each.value.cpu_request
              memory = each.value.memory_request
            }
            limits = {
              cpu    = each.value.cpu_limit
              memory = each.value.memory_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = each.value.liveness_initial_delay
            period_seconds        = each.value.liveness_period
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = each.value.readiness_initial_delay
            period_seconds        = each.value.readiness_period
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