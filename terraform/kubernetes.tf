# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                      = "${var.env}-KubeAKS"
  location                  = azurerm_resource_group.kuberg.location
  resource_group_name       = azurerm_resource_group.kuberg.name
  dns_prefix                = "${var.env}-KubeAKS"
  kubernetes_version        = var.aks_cluster_version

  default_node_pool {
    name                    = "default"
    orchestrator_version    = var.aks_cluster_version
    node_count              = var.aks_node_count
    vm_size                 = var.aks_vm_size
    vnet_subnet_id          = data.azurerm_subnet.vnet_subnet1.id
    enable_auto_scaling     = var.aks_auto_scaling_enabled
    min_count               = var.aks_auto_scaling_min_count
    max_count               = var.aks_auto_scaling_max_count
  }

  network_profile {
    network_plugin          = "azure"
    dns_service_ip          = "172.16.0.10"
    docker_bridge_cidr      = "172.17.0.1/16"
    service_cidr            = "172.16.0.0/16"
  }

  identity {
    type = "SystemAssigned"
  }

  tags                      = var.tags
  depends_on                = [azurerm_virtual_network.vnet]
}