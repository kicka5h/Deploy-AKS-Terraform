variable "aks_auto_scaling_enabled" {
  description = "Enable autoscaling when set to true"
  type = bool
  default = false
}

variable "aks_auto_scaling_min_count" {
  description = "Minimum number of nodes that should exist in the node pool"
  type = number
  default = null
}

variable "aks_auto_scaling_max_count" {
  description = "Maximum number of nodes that should exist in the node pool"
  type = number
  default = null
}

variable "aks_cluster_version" {
  description = "AKS cluster version"
  default = "1.22.11"
}

variable "aks_node_count" {
  description = "AKS node count"
  type = number
  default = 1
}

variable "aks_vm_size" {
  description = "AKS VM size"
  default = "Standard_D2_v2"
}

variable "container_registry_georeplication_location" {
  description = "Container registry geoeplication location"
  type = list(string)
  default = null
}

variable "container_registry_sku" {
  description = "Container registry SKU"
  default = "Standard"
}

variable "env" {
  description = "Environment name"
  default = "lab"
}

variable "location" {
  description = "Resource location"
  default = "westus"
}

variable "tags" {
  description = "Default tags to apply to resources"
  type = map
  default = {
    Environment  = "Lab"
    Application = "Kubernetes"
  }
}

variable "vnet_address_space" {
  description = "VNet address space"
  type = list(string)
  default = ["10.11.0.0/16"]
}

variable "vnet_dns_servers" {
  description = "VNet DNS Servers"
  type = list(string)
  default = [""]
}

variable "vnet_subnet1_address_prefix" {
  description = "VNet Subnet1 subnet address prefix"
  default = "10.11.2.0/21"
}