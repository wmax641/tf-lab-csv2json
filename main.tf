provider "aws" {
  region = "ap-southeast-2"
}
provider "archive" {}

terraform {
  backend "local" {
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }
}
#locals {
#  common_tags = {
#    "Project"          = "${var.base_name}"
#    "contact"                = "wmax641"
#  }
#}
