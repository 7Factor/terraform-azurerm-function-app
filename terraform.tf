terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    validation = {
      source = "tlkamp/validation"
      version = "~> 1.1"
    }
  }
}
