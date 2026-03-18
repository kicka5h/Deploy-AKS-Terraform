# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                     = "${var.env}KubeCR"
  resource_group_name      = azurerm_resource_group.kuberg.name
  location                 = azurerm_resource_group.kuberg.location
  sku                      = var.container_registry_sku
  admin_enabled            = false
  georeplication_locations  = var.container_registry_georeplication_location
  tags                     = var.tags
}

# Role Assignment - AcrPull for Primary AKS
resource "azurerm_role_assignment" "aks_sp_container_registry" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  depends_on           = [azurerm_kubernetes_cluster.aks, azurerm_container_registry.acr]
}

# Role Assignment - AcrPull for DR AKS
resource "azurerm_role_assignment" "aks_dr_sp_container_registry" {
  count                = var.enable_dr ? 1 : 0
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks_dr[0].kubelet_identity[0].object_id
  depends_on           = [azurerm_kubernetes_cluster.aks_dr, azurerm_container_registry.acr]
}
