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

variable "vpc_id" {
  type                    = string
  description             = "Specify a VPC ID where VPC bound resources will be created"
}

variable "subnet_ids" {
  type                    = list 
  description             = "Specify a list of Subnet IDs within above VPC for deployment"
}

variable "proxy_port" {
  type                  = number
  description           = "Specify the listen port of the NLB (i.e. proxy ingress port)"
}

## EC2 App Settings ##

variable "enable_ssm" {
  type                      = bool
  default                   = false
  description               = "Specify whether to enable SSM Session Manager for EC2; if enabled, create SSM VPC endpoints"
}

variable "ec2_instance_type" {
  type                    = string
  default                 = "t3.large"
  description             = "EC2 instance type for proxy server instances"
}

variable "ssh_keypair_name" {
  type                    = string
  description             = "Name of an existing SSH keypair"
}

variable "ssh_private_key_file" {
  type                    = string
  description             = "Specify the path to the private key file used for SSH connections"
}

variable "ssh_ingress_port" {
  type                  = number
  description           = "Specify the listen port of NLB for SSH tunneling to EC2"
}

variable "proxy_allowed_ingress_cidr_list" {
  type                  = list
  default               = [] 
  description           = "Specify list of CIDR blocks that are allowed to connect into AppSvr EC2 via SSH"
}

