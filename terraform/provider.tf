# Azure provider
provider "azurerm" {
  features {}
}

# Kubernetes provider - Primary cluster
provider "kubernetes" {
  alias                  = "primary"
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

# Helm provider - Primary cluster
provider "helm" {
  alias = "primary"
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

# Kubernetes provider - DR cluster
provider "kubernetes" {
  alias                  = "dr"
  host                   = var.enable_dr ? azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].host : "https://localhost"
  client_certificate     = var.enable_dr ? base64decode(azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].client_certificate) : ""
  client_key             = var.enable_dr ? base64decode(azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].client_key) : ""
  cluster_ca_certificate = var.enable_dr ? base64decode(azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].cluster_ca_certificate) : ""
}

# Helm provider - DR cluster
provider "helm" {
  alias = "dr"
  kubernetes {
    host                   = var.enable_dr ? azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].host : "https://localhost"
    client_certificate     = var.enable_dr ? base64decode(azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].client_certificate) : ""
    client_key             = var.enable_dr ? base64decode(azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].client_key) : ""
    cluster_ca_certificate = var.enable_dr ? base64decode(azurerm_kubernetes_cluster.aks_dr[0].kube_config[0].cluster_ca_certificate) : ""
  }
}
