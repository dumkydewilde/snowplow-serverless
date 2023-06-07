terraform {
  required_version = "~> 1"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.68.0"
    }
  }
}