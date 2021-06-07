resource "azurerm_resource_group" "aks" {
  name     = "${var.prefix}-webapp-rg"
  location = var.location
}

resource "azurerm_resource_group" "net" {
  name     = "${var.prefix}-net-rg"
  location = var.location
}

resource "azurerm_resource_group" "sa" {
  name     = "${var.prefix}-sa-rg"
  location = var.location
}

resource "azurerm_resource_group" "loganalytics" {
  name     = "${var.prefix}-law-rg"
  location = var.location
}

