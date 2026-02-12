resource "azurerm_application_insights" "web_app" {
  count = var.app_insights_name == null ? 1 : 0

  name = templatestring(var.resource_name_options.template, merge(local.name_template_vars, {
    resource_type = "appi"
  }))
  resource_group_name = local.resource_group.name
  location            = local.resource_group.location

  // If workspace id provided, create workspace-based; else classic
  workspace_id = var.log_analytics_workspace_id

  application_type = "web"

  tags = var.global_tags
}

data "azurerm_application_insights" "web_app" {
  count = var.app_insights_name == null ? 0 : 1

  name                = var.app_insights_name
  resource_group_name = local.resource_group.name
}

locals {
  app_insights = var.app_insights_name != null ? data.azurerm_application_insights.web_app[0] : azurerm_application_insights.web_app[0]
}