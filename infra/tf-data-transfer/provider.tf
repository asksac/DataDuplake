terraform {
  required_version        = ">= 1.6"
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
