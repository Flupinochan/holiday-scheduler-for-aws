terraform {
  required_version = ">= 1.14.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.38.0, < 7.0.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 7.25.0, < 8.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}
