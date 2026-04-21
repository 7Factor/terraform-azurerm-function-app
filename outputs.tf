output "function_app" {
  value = var.use_flex_consumption ? azurerm_function_app_flex_consumption.web_app[0] : azurerm_linux_function_app.web_app[0]
}

output "service_plan_id" {
  value = local.service_plan_id
}

output "application_insights" {
  value = local.app_insights
}

output "resource_group" {
  value = local.resource_group
}
