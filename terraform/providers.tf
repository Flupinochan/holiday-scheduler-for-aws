terraform {
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use latest AWS provider 5.x
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0" # Use latest Google provider 5.x
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
