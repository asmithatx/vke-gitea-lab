terraform {
  required_version = ">= 1.6"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "vultr" {
  api_key     = var.vultr_api_key
  rate_limit  = 700
  retry_limit = 3
}
