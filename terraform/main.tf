# ============================================================
# CISC 886 – Cloud Computing Project
# Student NetID: 25DJT3
# Region: us-east-1
# ============================================================

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
