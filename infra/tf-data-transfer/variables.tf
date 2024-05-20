variable "aws_profile" {
  type                    = string
  default                 = "default"
  description             = "Specify an aws profile name to be used for access credentials (run `aws configure help` for more information on creating a new profile)"
}

variable "aws_region" {
  type                    = string
  default                 = "us-east-1"
  description             = "Specify the AWS region to be used for resource creations"
}

variable "aws_env" {
  type                    = string
  default                 = "dev"
  description             = "Specify a value for the Environment tag"
}

variable "app_name" {
  type                    = string
  default                 = "DataDuplake"
  description             = "Specify an application or project name, used primarily for tagging"
}

variable "app_shortcode" {
  type                    = string
  default                 = "ddlake"
  description             = "Specify a short-code or pneumonic for this application or project, used for resource name prefix"
}

variable "gcp_project_id" {
  type                    = string 
  description             = "GCP Project Id that Hub connects to"
}

variable "gcp_access_keyfile" {
  type                    = string 
  description             = "Full path to GCP credentials file"
}

