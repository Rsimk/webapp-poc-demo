resource "azurerm_postgresql_server" "webapp-poc-demo-db-srv" {
  name                = "webapp-poc-demo-db-srv"
  location            = azurerm_resource_group.pg-db.location
  resource_group_name = azurerm_resource_group.pg-db.name

  sku_name = "GP_Gen5_2"

  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = true
  auto_grow_enabled            = true

  administrator_login          = "pgadmin"
  administrator_login_password = "pgadmin"
  version                      = "11"
  ssl_enforcement_enabled      = true
}

resource "azurerm_postgresql_database" "webapp-poc-demo-db" {
  name                = "webapp-poc-demo-db"
  resource_group_name = azurerm_resource_group.pg-db.name
  server_name         = azurerm_postgresql_server.webapp-poc-demo-db-srv.name
  charset             = "UTF8"
  collation           = "English_United States.1252"
}