output "acr_login_server" {
  description = "ACR login server URL"
  value       = data.azurerm_container_registry.acr.login_server
}

output "deployed_applications" {
  description = "List of deployed applications"
  value = {
    for key, config in local.app_env_combinations :
    key => {
      app_name    = config.app_name
      environment = config.env_name
      namespace   = config.namespace
      replicas    = config.replicas
    }
  }
}

output "namespaces" {
  description = "Created namespaces"
  value       = [for ns in kubernetes_namespace.env : ns.metadata[0].name]
}