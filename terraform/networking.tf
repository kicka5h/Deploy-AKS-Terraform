# Virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.env}-KubeVNET"
  resource_group_name = var.kuberg.name
  location            = var.kuberg.location
  address_space       = var.vnet_address_space
  tags                = var.tags
  dns_servers         = var.vnet_dns_servers
  subnet {
    name           = "${var.env}Subnet1"
    address_prefix = var.vnet_subnet1_address_prefix
  }
}

# Virtual network subnets data
data "azurerm_subnet" "vnet_subnet1" {
  name                 = "${var.env}Subnet1"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_virtual_network.vnet.resource_group_name
  depends_on           = [azurerm_virtual_network.vnet]
}