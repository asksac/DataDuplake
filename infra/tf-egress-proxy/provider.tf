terraform {
  required_version        = ">= 0.13"
  required_providers {
    aws                   = ">= 3.11.0"
  }
}

provider "aws" {
  profile                 = var.aws_profile
  region                  = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
