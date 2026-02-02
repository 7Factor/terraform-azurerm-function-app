output "function_app" {
  value = var.use_flex_consumption ? azurerm_function_app_flex_consumption.web_app[0] : azurerm_linux_function_app.web_app[0]
}

output "service_plan" {
  value = azurerm_service_plan.web_app
}

output "application_insights" {
  value = azurerm_application_insights.web_app
}
