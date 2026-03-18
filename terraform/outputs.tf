# Primary AKS outputs
output "aks_cluster_name" {
  description = "Primary AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_fqdn" {
  description = "Primary AKS cluster FQDN"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "aks_kube_config" {
  description = "Primary AKS kubeconfig (sensitive)"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

# DR AKS outputs
output "aks_dr_cluster_name" {
  description = "DR AKS cluster name"
  value       = var.enable_dr ? azurerm_kubernetes_cluster.aks_dr[0].name : null
}

output "aks_dr_cluster_fqdn" {
  description = "DR AKS cluster FQDN"
  value       = var.enable_dr ? azurerm_kubernetes_cluster.aks_dr[0].fqdn : null
}

output "aks_dr_kube_config" {
  description = "DR AKS kubeconfig (sensitive)"
  value       = var.enable_dr ? azurerm_kubernetes_cluster.aks_dr[0].kube_config_raw : null
  sensitive   = true
}

# Front Door outputs
output "frontdoor_endpoint_hostname" {
  description = "Front Door endpoint hostname"
  value       = var.enable_dr ? azurerm_cdn_frontdoor_endpoint.main[0].host_name : null
}

output "frontdoor_profile_id" {
  description = "Front Door profile ID"
  value       = var.enable_dr ? azurerm_cdn_frontdoor_profile.main[0].id : null
}

# ACR output
output "acr_login_server" {
  description = "ACR login server URL"
  value       = azurerm_container_registry.acr.login_server
}
