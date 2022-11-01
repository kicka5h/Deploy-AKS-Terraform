# Resource Group - Azure Container Registry
resource "azurerm_resource_group" "acrrg" {
  name                      = "${var.env}-kubeCRRG"
  location                  = var.location
  tags                      = var.tags
}

# Resource Group - Azure Kubernetes Service
resource "azurerm_resource_group" "kuberg" {
  name                      = "${var.env}-kubeRG"
  location                  = var.location
  tags                      = var.tags
}
