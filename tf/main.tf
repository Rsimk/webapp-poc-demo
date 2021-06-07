provider "azurerm" {
  version = "2.39.0"
  features {
  }
}

provider "azuread" {
  version = "1.0.0"
}
# use azure for backend state
terraform {
    backend "azurerm" {}
}
terraform {
  required_version = "~> 0.13"
}
