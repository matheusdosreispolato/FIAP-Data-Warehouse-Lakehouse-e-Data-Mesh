terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "FIAP-DW-Lakehouse-DataMesh"
      Lab         = "03-DataModeling-DataWarehouse"
      ManagedBy   = "Terraform"
      Environment = "LearnerLab"
    }
  }
}
