aks_auto_scaling_enabled   = true
aks_auto_scaling_min_count = 2
aks_auto_scaling_max_count = 5
aks_cluster_version        = "1.22.11"
aks_node_count             = 3
aks_vm_size                = "Standard_D2_v2"
container_registry_sku     = "Standard"
env                        = "dev"
location                   = "westus"
tags = {
  Environment = "dev"
  Application = "Kubernetes"
}
vnet_address_space          = ["10.21.0.0/16"]
vnet_dns_servers            = null
vnet_subnet1_address_prefix = "10.21.2.0/24"

# DR / Failover Configuration
enable_dr                      = false
dr_location                    = "eastus"
dr_vnet_address_space          = ["10.22.0.0/16"]
dr_vnet_subnet1_address_prefix = "10.22.2.0/24"
dr_aks_node_count              = 2
dr_aks_vm_size                 = "Standard_D2_v2"

# Front Door
frontdoor_sku      = "Premium_AzureFrontDoor"
frontdoor_waf_mode = "Prevention"

# Helm
helm_nginx_ingress_version = "4.11.3"
