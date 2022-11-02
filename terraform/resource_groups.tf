# Resource Group - Azure Kubernetes Service
resource "azurerm_resource_group" "kuberg" {
  name                      = "${var.env}-kubeRG"
  location                  = var.location
  tags                      = var.tags
}
