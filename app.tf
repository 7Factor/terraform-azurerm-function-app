locals {
  needs_acr_role         = var.private_acr_id != null
  needs_managed_identity = local.needs_kv_role || local.needs_acr_role

  # Identity type to use if the service needs a user-assigned identity
  assigned_identity_type = var.enable_system_assigned_identity ? "SystemAssigned, UserAssigned" : "UserAssigned"
}

resource "azurerm_user_assigned_identity" "web_app" {
  count = local.needs_managed_identity ? 1 : 0

  location            = local.resource_group.location
  resource_group_name = local.resource_group.name
  name = templatestring(var.resource_name_options.template, merge(local.name_template_vars, {
    resource_type = "id"
  }))
}

resource "azurerm_role_assignment" "acr_pull" {
  count = local.needs_acr_role ? 1 : 0

  scope                = var.private_acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.web_app[0].principal_id
}

# Use this terraform_data resource as a proxy for var.app_settings, so we can see changes to app_settings even 
# if some other values (like related to app insights or keyvault) are not known until after the terraform is applied
resource "terraform_data" "app_settings" {
  input = var.app_settings
}

resource "azurerm_linux_function_app" "web_app" {
  count = var.use_flex_consumption ? 0 : 1

  name = templatestring(var.resource_name_options.template, merge(local.name_template_vars, {
    resource_type = "func"
  }))
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  service_plan_id     = local.service_plan_id

  storage_account_name       = azurerm_storage_account.function_app_storage.name
  storage_account_access_key = azurerm_storage_account.function_app_storage.primary_access_key

  https_only                         = var.site_config.https_only
  client_certificate_enabled         = var.site_config.client_certificate_enabled
  client_certificate_mode            = var.site_config.client_certificate_mode
  client_certificate_exclusion_paths = var.site_config.client_certificate_exclusion_paths

  identity {
    type = local.needs_managed_identity ? local.assigned_identity_type : "SystemAssigned"
    identity_ids = local.needs_managed_identity ? [
      azurerm_user_assigned_identity.web_app[0].id
    ] : null
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.web_app.connection_string
    application_insights_key               = azurerm_application_insights.web_app.instrumentation_key

    always_on                         = var.site_config.always_on
    api_definition_url                = var.site_config.api_definition_url
    api_management_api_id             = var.site_config.api_management_api_id
    app_command_line                  = var.site_config.app_command_line
    default_documents                 = var.site_config.default_documents
    ftps_state                        = var.site_config.ftps_state
    health_check_path                 = var.site_config.health_check_path
    health_check_eviction_time_in_min = var.site_config.health_check_eviction_time_in_min
    http2_enabled                     = var.site_config.http2_enabled
    load_balancing_mode               = var.site_config.load_balancing_mode
    minimum_tls_version               = var.site_config.minimum_tls_version
    use_32_bit_worker                 = var.site_config.use_32_bit_worker
    vnet_route_all_enabled            = var.site_config.vnet_route_all_enabled
    websockets_enabled                = var.site_config.websockets_enabled
    worker_count                      = var.site_config.worker_count

    application_stack {
      docker {
        image_name        = var.application_stack.docker_image_name
        image_tag         = var.application_stack.docker_image_tag
        registry_url      = var.application_stack.docker_registry_url
        registry_username = var.application_stack.docker_registry_username
        registry_password = var.application_stack.docker_registry_password
      }
      dotnet_version              = contains(["dotnet", "dotnet-isolated"], var.application_stack.runtime_name) ? var.application_stack.runtime_version : null
      use_dotnet_isolated_runtime = var.application_stack.runtime_name == "dotnet-isolated"
      java_version                = var.application_stack.runtime_name == "java" ? var.application_stack.runtime_version : null
      node_version                = var.application_stack.runtime_name == "node" ? var.application_stack.runtime_version : null
      python_version              = var.application_stack.runtime_name == "python" ? var.application_stack.runtime_version : null
      powershell_core_version     = var.application_stack.runtime_name == "powershell" ? var.application_stack.runtime_version : null
      use_custom_runtime          = var.application_stack.runtime_name == "custom"
    }

    cors {
      allowed_origins     = var.cors.allowed_origins
      support_credentials = var.cors.support_credentials
    }
  }

  app_settings = merge(
    terraform_data.app_settings.input,
    module.app_secrets.app_settings_bindings
  )

  tags = var.global_tags

  depends_on = [
    module.app_secrets
  ]
}

resource "azurerm_function_app_flex_consumption" "web_app" {
  count = var.use_flex_consumption ? 1 : 0

  name = templatestring(var.resource_name_options.template, merge(local.name_template_vars, {
    resource_type = "func"
  }))
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location
  service_plan_id     = local.service_plan_id

  runtime_name    = var.application_stack.runtime_name
  runtime_version = var.application_stack.runtime_version

  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.function_app_storage.primary_blob_endpoint}${azurerm_storage_container.function_app_storage[0].name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.function_app_storage.primary_access_key

  https_only                         = var.site_config.https_only
  client_certificate_enabled         = var.site_config.client_certificate_enabled
  client_certificate_mode            = var.site_config.client_certificate_mode
  client_certificate_exclusion_paths = var.site_config.client_certificate_exclusion_paths

  maximum_instance_count = var.flex_settings.maximum_instance_count
  instance_memory_in_mb  = var.flex_settings.instance_memory_in_mb

  identity {
    type = local.needs_managed_identity ? local.assigned_identity_type : "SystemAssigned"
    identity_ids = local.needs_managed_identity ? [
      azurerm_user_assigned_identity.web_app[0].id
    ] : null
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.web_app.connection_string
    application_insights_key               = azurerm_application_insights.web_app.instrumentation_key

    api_definition_url                = var.site_config.api_definition_url
    api_management_api_id             = var.site_config.api_management_api_id
    app_command_line                  = var.site_config.app_command_line
    default_documents                 = var.site_config.default_documents
    health_check_path                 = var.site_config.health_check_path
    health_check_eviction_time_in_min = var.site_config.health_check_eviction_time_in_min
    http2_enabled                     = var.site_config.http2_enabled
    load_balancing_mode               = var.site_config.load_balancing_mode
    minimum_tls_version               = var.site_config.minimum_tls_version
    use_32_bit_worker                 = var.site_config.use_32_bit_worker
    vnet_route_all_enabled            = var.site_config.vnet_route_all_enabled
    websockets_enabled                = var.site_config.websockets_enabled
    worker_count                      = var.site_config.worker_count

    cors {
      allowed_origins     = var.cors.allowed_origins
      support_credentials = var.cors.support_credentials
    }
  }

  app_settings = merge(
    terraform_data.app_settings.input,
    module.app_secrets.app_settings_bindings
  )

  tags = var.global_tags

  depends_on = [
    module.app_secrets
  ]
}

resource "validation_warnings" "warns" {
  warning {
    condition = var.site_config.always_on != null && var.use_flex_consumption
    summary   = "always_on is not supported when use_flex_consumption is enabled"
  }

  warning {
    condition = var.site_config.ftps_state != null && var.use_flex_consumption
    summary   = "ftps_state is not supported when use_flex_consumption is enabled"
  }
}

// Only create diagnostic settings if a LAW is provided
resource "azurerm_monitor_diagnostic_setting" "app_to_law" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name = templatestring(var.resource_name_options.template, merge(local.name_template_vars, {
    resource_type = "diag"
  }))
  target_resource_id         = var.use_flex_consumption ? azurerm_function_app_flex_consumption.web_app[0].id : azurerm_linux_function_app.web_app[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(var.diagnostic_log_category_groups)
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = toset(var.diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = toset(var.diagnostic_metric_categories)
    content {
      category = enabled_metric.value
    }
  }
}
