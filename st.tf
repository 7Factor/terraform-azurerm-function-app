locals {
  st_max_len = 24

  unsafe_st_name = templatestring(var.resource_name_options.template_safe, merge(local.name_template_vars, {
    app_name      = local.safe_app_name
    resource_type = "st"
  }))
  st_name_over_budget     = length(local.unsafe_st_name) > local.st_max_len ? length(local.unsafe_st_name) - local.st_max_len : 0
  st_safe_app_name_substr = substr(local.safe_app_name, 0, length(local.safe_app_name) - local.st_name_over_budget)
  st_name = lower(templatestring(var.resource_name_options.template_safe, merge({
    app_name      = local.st_safe_app_name_substr
    resource_type = "st"
  })))
}

resource "azurerm_storage_account" "function_app_storage" {
  count = var.storage.existing_name != null ? 0 : 1

  name                     = local.st_name
  resource_group_name      = local.resource_group.name
  location                 = local.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = var.global_tags
}

data "azurerm_storage_account" "existing_account" {
  count = var.storage.existing_name != null ? 1 : 0

  name                = var.storage.existing_name
  resource_group_name = var.storage.existing_rg_name != null ? var.storage.existing_rg_name : local.resource_group.name
}

locals {
  function_app_storage_account = var.storage.existing_name != null ? data.azurerm_storage_account.existing_account[0] : azurerm_storage_account.function_app_storage[0]
}

resource "azurerm_storage_container" "function_app_storage" {
  count = var.use_flex_consumption && var.storage.existing_container_name != null ? 1 : 0

  name                  = "function-app-storage"
  storage_account_id    = local.function_app_storage_account.id
  container_access_type = "private"
}

data "azurerm_storage_container" "existing_container" {
  count = var.use_flex_consumption && var.storage.existing_container_name != null ? 1 : 0

  name               = var.storage.existing_container_name
  storage_account_id = local.function_app_storage_account.id
}

locals {
  function_app_storage_container = try(data.azurerm_storage_container.existing_container[0], azurerm_storage_container.function_app_storage[0], null)
}