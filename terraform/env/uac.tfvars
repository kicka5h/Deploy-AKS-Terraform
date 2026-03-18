aks_auto_scaling_enabled   = true
aks_auto_scaling_min_count = 3
aks_auto_scaling_max_count = 10
aks_cluster_version        = "1.22.11"
aks_node_count             = 3
aks_vm_size                = "Standard_D4_v2"
container_registry_sku     = "Premium"
env                        = "uac"
location                   = "westus"
tags = {
  Environment = "uac"
  Application = "Kubernetes"
}
vnet_address_space          = ["10.31.0.0/16"]
vnet_dns_servers            = null
vnet_subnet1_address_prefix = "10.31.2.0/24"

# DR / Failover Configuration
enable_dr                      = true
dr_location                    = "eastus"
dr_vnet_address_space          = ["10.32.0.0/16"]
dr_vnet_subnet1_address_prefix = "10.32.2.0/24"
dr_aks_node_count              = 3
dr_aks_vm_size                 = "Standard_D4_v2"

# Front Door
frontdoor_sku      = "Premium_AzureFrontDoor"
frontdoor_waf_mode = "Prevention"

# Helm
helm_nginx_ingress_version = "4.11.3"
