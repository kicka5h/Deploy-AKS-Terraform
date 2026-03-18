# Resource Group - Primary AKS
resource "azurerm_resource_group" "kuberg" {
  name     = "${var.env}-kubeRG"
  location = var.location
  tags     = var.tags
}

# Resource Group - DR AKS
resource "azurerm_resource_group" "kuberg_dr" {
  count    = var.enable_dr ? 1 : 0
  name     = "${var.env}-kubeRG-dr"
  location = var.dr_location
  tags     = var.tags
}

# Resource Group - Front Door (global resource, placed in primary region)
resource "azurerm_resource_group" "frontdoor" {
  count    = var.enable_dr ? 1 : 0
  name     = "${var.env}-frontdoorRG"
  location = var.location
  tags     = var.tags
}
