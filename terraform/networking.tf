# Virtual network - Primary
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.env}-KubeVNET"
  resource_group_name = azurerm_resource_group.kuberg.name
  location            = azurerm_resource_group.kuberg.location
  address_space       = var.vnet_address_space
  tags                = var.tags
  dns_servers         = var.vnet_dns_servers
  subnet {
    name           = "${var.env}Subnet1"
    address_prefix = var.vnet_subnet1_address_prefix
  }
}

# Virtual network subnets data - Primary
data "azurerm_subnet" "vnet_subnet1" {
  name                 = "${var.env}Subnet1"
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name  = azurerm_virtual_network.vnet.resource_group_name
  depends_on           = [azurerm_virtual_network.vnet]
}

# Virtual network - DR
resource "azurerm_virtual_network" "vnet_dr" {
  count               = var.enable_dr ? 1 : 0
  name                = "${var.env}-KubeVNET-dr"
  resource_group_name = azurerm_resource_group.kuberg_dr[0].name
  location            = azurerm_resource_group.kuberg_dr[0].location
  address_space       = var.dr_vnet_address_space
  tags                = var.tags
  dns_servers         = var.vnet_dns_servers
  subnet {
    name           = "${var.env}Subnet1-dr"
    address_prefix = var.dr_vnet_subnet1_address_prefix
  }
}

# Virtual network subnets data - DR
data "azurerm_subnet" "vnet_subnet1_dr" {
  count                = var.enable_dr ? 1 : 0
  name                 = "${var.env}Subnet1-dr"
  virtual_network_name = azurerm_virtual_network.vnet_dr[0].name
  resource_group_name  = azurerm_virtual_network.vnet_dr[0].resource_group_name
  depends_on           = [azurerm_virtual_network.vnet_dr]
}
