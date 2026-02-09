# terraform-azurerm-function-app
A lightweight, batteries-included Terraform module for deploying Azure Functions on Linux with sensible defaults and optional integrations.

What you get:

- Azure Function App (Linux), either:
  - Dedicated/App Service Plan, or
  - Flex Consumption plan (preview GA-ready pattern)
- Backing Storage Account and Blob Container (or use existing)
- Application Insights (workspace-based if a Log Analytics Workspace ID is provided; classic otherwise)
- Optional diagnostic settings streaming to Log Analytics
- Optional Key Vault (with RBAC), placeholder secrets, and app settings references
- User-assigned managed identity for Key Vault and/or ACR access
- Optional ACR pull role assignment for containerized functions (non-flex)
- Simple naming and tagging

## Why this module?
Spin up an opinionated Azure Function App quickly, with:

- Minimal inputs to get running
- Safe defaults that work for most teams
- Opt-in features (Key Vault, LAW, ACR) when you need them
- Works with both dedicated plan and Flex Consumption

## Usage

### Basic example
```terraform-hcl
locals {
  env_name = "dev"
}

module "function_app" {
  source  = "7Factor/function-app/azurerm"
  version = "~> 1.0"

  app_name = "orders-worker"

  resource_name_options = {
    # Available template variables are `app_name` and `resource_type`, escaped with $$
    # You can use other locals or variables using a single $
    # Example: resolves to acme-rg-orders-worker-dev for a resource group
    template      = "acme-$${resource_type}-$${app_name}-${local.env_name}"
    # Example: resolves to acmekvordersworkerdev for a Key Vault
    template_safe = "acme$${resource_type}$${app_name}${local.env_name}"
  }

  # Choose a runtime
  application_stack = {
    runtime_name    = "dotnet-isolated"
    runtime_version = "8.0"
  }

  # Optional: App settings passed directly to the Function App
  app_settings = {
    FUNCTIONS_WORKER_PROCESS_COUNT = "2"
    AzureWebJobsStorage__account   = "ref-only"
  }

  # Optional: Define Key Vault secrets and bind them to app settings
  app_secrets = [
    {
      name             = "Db-ConnectionString"
      app_setting_name = "ConnectionStrings__Database"
      initial_value    = "sample" # optional; defaults to ""
    },
    {
      name             = "Api-Key"
      app_setting_name = "MyApi__Key"
    },
    {
      name = "Unbound-Secret"
      # Not bound to app settings (created/managed in KV only)
    }
  ]

  # Optional: Centralized logging
  # log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-observability/providers/Microsoft.OperationalInsights/workspaces/law-observability"

  global_tags = {
    environment = "dev"
    owner       = "platform-team"
  }
}
```

### Flex Consumption
```terraform-hcl
module "function_app_flex" {
  source  = "7Factor/function-app/azurerm"
  version = "~> 1.0"

  app_name            = "orders-flex"
  use_flex_consumption = true

  application_stack = {
    runtime_name    = "python"
    runtime_version = "3.11"
  }

  flex_settings = {
    maximum_instance_count = 20
    instance_memory_in_mb  = 2048
  }

  app_settings = {
    FUNCTIONS_WORKER_PROCESS_COUNT = "1"
  }

  global_tags = {
    environment = "dev"
  }
}
```

### Containerized functions (dedicated plan only)
```terraform-hcl
module "function_app_container" {
  source  = "7Factor/function-app/azurerm"
  version = "~> 1.0"

  app_name = "orders-container"

  application_stack = {
    runtime_name             = "custom" # container-based
    docker_image_name        = "myrepo/orders-func"
    docker_image_tag         = "1.2.3"
    docker_registry_url      = "myregistry.azurecr.io"
    docker_registry_username = "acr-username"     # or omit when using ACR + managed identity pull
    docker_registry_password = "acr-password"     # use a secret store/CI variable in real setups
  }

  # Grant AcrPull to the app’s user-assigned identity
  private_acr_id = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerRegistry/registries/<acr-name>"

  global_tags = {
    environment = "dev"
  }
}
```

After apply:

- If you set app_secrets, the module creates:
  - A Key Vault (RBAC-enabled) unless you point to an existing one
  - Secrets with the given names (initial values default to "", and Terraform ignores future changes to value)
  - App settings on the Function App that reference the secrets using non-versioned URIs
- Populate real secret values later via Azure Portal or CI. The Function App will resolve the latest version via its managed identity.
- If you set private_acr_id (and use a non-flex plan), the module creates a user-assigned identity and grants AcrPull on your ACR.

## Inputs
### Required
- __app_name__ (string, required)
  - Base name for resources (combined with template).

### Recommended
- _resource_name_options_ (object, default: {})
  - _template_ (string, default: "$${resource_type}-$${app_name}")
  - _template_safe_ (string, default: "$${resource_type}$${app_name}")
- _app_settings_ (map(string), default: {})
Additional application settings added to the Function App.
- _app_secrets_ (list(object), default: [])
  - __name__ (string, required): Key Vault secret name.
  - _app_setting_name_ (string, optional): App setting key to bind via Key Vault reference. If omitted, the secret is created but not bound.
  - _external_ (bool, default: false): If true, Terraform will not create the secret; it is assumed to already exist.
  - _initial_value_ (string, optional): Seed value for first deploy. Subsequent changes are ignored.
  - _tags_ (map(string), optional): Tags to apply to an individual secret.
- _application_stack_ (object)
  - For dedicated plan: optional but recommended.
  - For flex consumption: `runtime_name` and `runtime_version` are required.
  - Supports: `node`, `dotnet`, `dotnet-isolated`, `powershell`, `python`, `java`, `custom` (custom typically for containers on dedicated plan)

### Optional
- _use_flex_consumption_ (bool, default: false)
Switch to flex consumption plan. __Note__: dotnet runtime must be `dotnet-isolated` for .NET workloads; `custom` and docker are not supported on flex
- _site_config_ (object)
  - Mirrors `azurerm_linux_function_app` and `azurerm_function_app_flex_consumption` supported settings with module-level conveniences:
  - _https_only_ (bool)
  - _client_certificate_enabled_ (bool)
  - _client_certificate_mode_ (string)
  - _client_certificate_exclusion_paths_ (string)
  - _virtual_network_subnet_id_ (string)
  - Logging settings (disk quota, retention)
  - Plus many standard Function App flags (see variable docs)
  - Not supported on flex: `always_on`, `builtin_logging_enabled`, `ftp_publish_basic_authentication_enabled`, `ftps_state`
- _flex_settings_ (object, default: {})
  - _maximum_instance_count_ (number, default: 1)
  - _instance_memory_in_mb_ (number, default: 1024)
- _connection_strings_ (list(object), default: [])
  - __name__ (string)
  - __type__ (string)
  - __secret_name__ (string; must match a secret in app_secrets)
- _log_analytics_workspace_id_ (string, default: null)
  - If provided, Application Insights is workspace-based and diagnostic settings send logs/metrics to this workspace.
- _global_tags_ (map(string), default: {})
  - Tags applied to all resources. Often used for environment and owning team.
- _resource_group_name_ (string, default: null)
  - Existing Resource Group name. If not provided, a new RG is created in location.
- _app_insights_name_ (string, default: null)
  - Use an existing Application Insights by name (in the target RG); otherwise one is created.
- _location_ (string, default: "eastus2")
- _service_plan_sku_ (string, default: "B2")
  - Size for the App Service Plan (dedicated plan only). Ignored if `service_plan_id` is provided or flex is used.
- _service_plan_id_ (string, default: null)
  - Use an existing App Service Plan (dedicated plan only).
- _diagnostic_log_category_groups_ (list(string), default: ["allLogs"])
- _diagnostic_log_categories_ (list(string), default: [])
- _diagnostic_metric_categories_ (list(string), default: ["AllMetrics"])
- _enable_system_assigned_identity_ (bool, default: false)
  - Adds a system-assigned identity in addition to the user-assigned identity when needed.
- _key_vault_ (object, default: {})
  - Ignored if no app_secrets are provided.
  - _sku_ (string, default: "standard")
  - _purge_protection_enabled_ (bool, default: false)
  - _soft_delete_retention_days_ (number, default: 7)
  - _existing_name_ (string, default: null)
  - _existing_rg_name_ (string, default: null)
- _storage_ (object, default: {})
  - Use existing Storage Account and/or Container for functions artifacts:
  - _existing_name_ (string, default: null)
  - _existing_container_name_ (string, default: null)
  - _existing_rg_name_ (string, default: null)
- _sticky_settings_ (object, default: null)
  - _app_setting_names_ (list(string))
  - _connection_string_names_ (list(string))
- _private_acr_id_ (string, default: null)
  - Optional ID of a private ACR to grant AcrPull for containerized functions (not supported with flex)

## Outputs
- __function_app__
- __service_plan_id__
- __application_insights__
- __resource_group__

## Notes
- Flex vs dedicated
  - When use_flex_consumption = true:
  - docker/custom not supported
  - dotnet (in-process) not supported; use dotnet-isolated
  - Some site_config fields are not supported (the module warns accordingly)
- Key Vault values
  - initial_value is intended as a seed only; Terraform ignores future changes to secret values by design
  - Rotate/manage real values outside of Terraform (Portal, CLI, or CI pipelines)
- ACR integration
  - If private_acr_id is set, a user-assigned identity is created and granted AcrPull
  - Container credentials in application_stack can be omitted when using ACR + managed identity