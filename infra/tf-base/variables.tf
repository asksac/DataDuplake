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

variable "db_vpc_id" {
  type                    = string
  description             = "Specify a VPC ID where VPC bound resources will be created"
}

variable "db_subnet_ids" {
  type                    = list 
  description             = "Specify a list of Subnet IDs within above VPC for deployment"
}

/*
variable "az_count" {
  type                    = number  
  description             = "Specify count of AZs that will be used to deploy infrastructure over"
}
*/

## RDS Aurora ##

variable "db_name" {
  type                    = string
  description             = "RDS Aurora Database Name"
}

variable "db_master_user" {
  type                    = string
  description             = "Aurora Database Master Username"
  #sensitive               = true
}
