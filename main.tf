// Tags
locals {
  tags = {
    owner       = var.tag_department
    region      = var.tag_region
    environment = var.environment
  }
}

// Existing Resources

/// Subscription ID

data "azurerm_subscription" "current" {
}
data "azurerm_client_config" "current" {}

// Random Suffix Generator

resource "random_integer" "deployment_id_suffix" {
  min = 100
  max = 999
}

// Resource Group

resource "azurerm_resource_group" "rg" {
  name     = "${var.class_name}-${var.student_name}-${var.environment}-${random_integer.deployment_id_suffix.result}-rg"
  location = var.location

  tags = local.tags
}


// Storage Account

resource "azurerm_storage_account" "storage" {
  name                     = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}st"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.tags
}

// Machine Learning

resource "azurerm_application_insights" "appinsights" {
  name                = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}-ai"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}

resource "azurerm_key_vault" "kv" {
  name                = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}kv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"
}

resource "azurerm_machine_learning_workspace" "mlws" {
  name                    = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}-workspace"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  application_insights_id = azurerm_application_insights.appinsights.id
  key_vault_id            = azurerm_key_vault.kv.id
  storage_account_id      = azurerm_storage_account.storage.id

  identity {
    type = "SystemAssigned"
  }
}

// Cosmos DB
resource "azurerm_cosmosdb_account" "db" {
  name                = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}-cdb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "MongoDB"

  capabilities {
    name = "EnableMongo"
  }

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }
}

// Windows Function App

resource "azurerm_service_plan" "svcpl" {
  name                = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}-svcpl"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Windows"
  sku_name            = "Y1"
}

resource "azurerm_windows_function_app" "wfa" {
  name                = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}-wfa"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.storage.name
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key
  service_plan_id            = azurerm_service_plan.svcpl.id

  site_config {}
}


// Azure Synapse Analytics

resource "azurerm_storage_account" "storage_hns" {
  name                     = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}st_hns"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true //to enable the hierarchical namespace. Required by Azure Synapse

  tags = local.tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "fs" {
  name               = "${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}fs"
  storage_account_id = azurerm_storage_account.storage_hns.id
}

resource "azurerm_synapse_workspace" "synapsews" {
  name                                 = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}-ws"
  resource_group_name                  = azurerm_resource_group.rg.name
  location                             = azurerm_resource_group.rg.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.fs.id
  sql_administrator_login              = "sqladminuser"
  sql_administrator_login_password     = var.sql_administrator_login_password

  managed_resource_group_name = "${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}-mgrsrc"

  aad_admin {
    login     = "AzureAD Admin"
    object_id = data.azurerm_client_config.current.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Env = var.environment
  }
}