variable "resource_name_options" {
  description = "(Optional) Options to adjust how resource names are generated"
  type = object({
    template      = optional(string)
    template_safe = optional(string)
  })
  default = {
    template      = "$${resource_type}-$${app_name}"
    template_safe = "$${resource_type}$${app_name}"
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", templatestring(var.resource_name_options.template, { resource_type = "", app_name = "" })))
    error_message = "The template value must contain only alphanumeric characters and hyphens."
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9]+$", templatestring(var.resource_name_options.template_safe, { resource_type = "", app_name = "" })))
    error_message = "The template_safe value must contain only alphanumeric characters."
  }
}

variable "app_name" {
  description = "Base name for the App Service (combined with prefix)."
  type        = string
}

locals {
  safe_app_name = replace(lower(var.app_name), "/[^a-z0-9]/", "")
  name_template_vars = {
    app_name = var.app_name
  }
}

variable "resource_group_name" {
  description = "(Optional) Existing Resource Group name. If this is not provided, a resource group will be created automatically."
  type        = string
  default     = null
}

variable "app_insights_name" {
  description = "(Optional) Existing Application Insights resource name. If this is not provided, a new Application Insights resource will be created automatically."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure location for resources. If a resource_group_id is provided, this value is ignored."
  type        = string
  default     = "eastus2"
}

variable "app_settings" {
  description = "Additional application settings to add to the app."
  type        = map(string)
  default     = {}
}

variable "app_secrets" {
  description = "List of secrets to create and optionally bind to app settings."
  type = list(object({
    name             = string
    app_setting_name = optional(string)
    initial_value    = optional(string)
    tags             = optional(map(string))
    external         = optional(bool, false)
  }))
  default   = []
  sensitive = true

  validation {
    condition     = length([for s in var.app_secrets : s.name]) == length(distinct([for s in var.app_secrets : s.name]))
    error_message = "Each app_secrets entry must have a unique 'name'."
  }
}

locals {
  app_secret_bindings = {
    for s in nonsensitive(var.app_secrets) : s.app_setting_name => s.name
    if s.app_setting_name != null && length(s.app_setting_name) > 0
  }
}

variable "connection_strings" {
  description = "List of connection strings to add to the application."
  type = list(object({
    name        = string
    type        = string
    secret_name = string
  }))
  default   = []
  sensitive = false

  validation {
    condition     = length([for s in var.connection_strings : s.name]) == length(distinct([for s in var.connection_strings : s.name]))
    error_message = "Each connection_strings entry must have a unique 'name'."
  }

  validation {
    condition     = alltrue([for cs in var.connection_strings : contains([for s in var.app_secrets : s.name], cs.secret_name)])
    error_message = "Each connection_strings entry must reference a secret in app_secrets."
  }
}

variable "use_flex_consumption" {
  type    = bool
  default = false
}

variable "application_stack" {
  type = object({
    runtime_name             = optional(string)
    runtime_version          = optional(string)
    docker_image_name        = optional(string)
    docker_image_tag         = optional(string)
    docker_registry_url      = optional(string)
    docker_registry_username = optional(string)
    docker_registry_password = optional(string)
  })

  validation {
    condition     = can(var.application_stack.runtime_name == null || contains(["node", "dotnet", "dotnet-isolated", "powershell", "python", "java", "custom"], var.application_stack.runtime_name))
    error_message = "application_stack.runtime_name must be one of: node, dotnet, dotnet-isolated, powershell, python, java, custom"
  }

  validation {
    condition     = can(var.use_flex_consumption && var.application_stack.runtime_name != "dotnet")
    error_message = "dotnet is not a supported runtime when use_flex_consumption is enabled. Please use dotnet-isolated instead."
  }

  validation {
    condition     = can(var.use_flex_consumption && var.application_stack.runtime_name != "custom")
    error_message = "custom is not a supported runtime when use_flex_consumption is enabled."
  }

  validation {
    condition     = can(var.use_flex_consumption && var.application_stack.docker_image_name == null && var.application_stack.docker_image_tag == null && var.application_stack.docker_registry_url == null && var.application_stack.docker_registry_username == null && var.application_stack.docker_registry_password == null)
    error_message = "docker is not a supported runtime when use_flex_consumption is enabled."
  }

  validation {
    condition     = can(var.use_flex_consumption && var.application_stack.runtime_name != null)
    error_message = "application_stack.runtime_name is required when use_flex_consumption is enabled"
  }

  validation {
    condition     = can(var.use_flex_consumption && var.application_stack.runtime_version != null)
    error_message = "application_stack.runtime_version is required when use_flex_consumption is enabled"
  }
}

locals {
  is_using_docker = var.application_stack.docker_image_name != null || var.application_stack.docker_image_tag != null || var.application_stack.docker_registry_url != null || var.application_stack.docker_registry_username != null || var.application_stack.docker_registry_password != null
}

variable "site_config" {
  type = object({
    always_on                                      = optional(bool) # not supported on flex
    api_definition_url                             = optional(string)
    api_management_api_id                          = optional(string)
    app_command_line                               = optional(string)
    builtin_logging_enabled                        = optional(bool) # not supported on flex
    client_certificate_enabled                     = optional(bool)
    client_certificate_exclusion_paths             = optional(string)
    client_certificate_mode                        = optional(string)
    default_documents                              = optional(list(string))
    ftp_publish_basic_authentication_enabled       = optional(bool)   # not supported on flex
    ftps_state                                     = optional(string) # not supported on flex
    health_check_path                              = optional(string)
    health_check_eviction_time_in_min              = optional(number)
    http2_enabled                                  = optional(bool, true)
    https_only                                     = optional(bool)
    load_balancing_mode                            = optional(string)
    logs_disk_quota_mb                             = optional(number)
    logs_retention_period_days                     = optional(number)
    minimum_tls_version                            = optional(string)
    runtime_scale_monitoring_enabled               = optional(bool)
    use_32_bit_worker                              = optional(bool, false)
    virtual_network_subnet_id                      = optional(string)
    vnet_route_all_enabled                         = optional(bool)
    webdeploy_publish_basic_authentication_enabled = optional(bool)
    websockets_enabled                             = optional(bool)
    worker_count                                   = optional(number)
  })
  default = {}
}

variable "flex_settings" {
  type = object({
    maximum_instance_count = optional(number, 1)
    instance_memory_in_mb  = optional(number, 1024)
  })
  default = {}
}

variable "cors" {
  type = object({
    allowed_origins     = optional(list(string))
    support_credentials = optional(bool)
  })
  default = {}
}

variable "service_plan_sku" {
  description = "App Service Plan size within the tier. Defaults to B2, and is only used for non-flex consumption functions."
  type        = string
  default     = "B2"
  nullable    = false
}

variable "service_plan_id" {
  description = "Existing App Service Plan ID. If this is not provided, a new plan will be created."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Optional Log Analytics Workspace ID. If provided, App Insights is workspace-based and diagnostics will send logs/metrics to LAW."
  type        = string
  default     = null
}

variable "diagnostic_log_category_groups" {
  description = "List of log category groups to enable for diagnostic settings."
  type        = list(string)
  default     = ["allLogs"]
}

variable "diagnostic_log_categories" {
  description = "List of log categories to enable for diagnostic settings."
  type        = list(string)
  default     = []
}

variable "diagnostic_metric_categories" {
  description = "List of metric categories to enable for diagnostic settings."
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "global_tags" {
  description = "Tags to apply to all resources (e.g., environment, cost-center)."
  type        = map(string)
  default     = {}
}

variable "enable_system_assigned_identity" {
  description = "Enable system-assigned managed identity on the app (in addition to the user-assigned one)."
  type        = bool
  default     = false
}

variable "key_vault" {
  type = object({
    sku                        = optional(string, "standard")
    purge_protection_enabled   = optional(bool, false)
    soft_delete_retention_days = optional(number, 7)
    existing_name              = optional(string, null)
    existing_rg_name           = optional(string, null)
  })
  default = {}
}

variable "storage" {
  type = object({
    existing_name           = optional(string, null)
    existing_container_name = optional(string, null)
    existing_rg_name        = optional(string, null)
  })
  default = {}
}

variable "sticky_settings" {
  description = "List of app settings names that should be marked as sticky (slot settings)."
  type = object({
    app_setting_names       = optional(list(string))
    connection_string_names = optional(list(string))
  })
  default = {}
}

variable "private_acr_id" {
  description = "Optional ID of a private ACR for pulling container images"
  type        = string
  default     = null

  validation {
    condition     = can(var.use_flex_consumption && var.private_acr_id == null)
    error_message = "Containers are not supported when use_flex_consumption is enabled."
  }
}
