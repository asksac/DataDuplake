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

# ----

variable "lambda_vpc_id" {
  type                    = string
  description             = "Specify a VPC ID for deploying the Lambda function(s) and Proxy VPC Endpoint"
}

variable "lambda_subnet_ids" {
  type                    = list
  description             = "Specify a list of Subnet IDs for deploying the Lambda function(s)"
}

variable "lambda_security_group_id" {
  type                    = string
  description             = "Specify a Security Group ID for deploying the Lambda function(s)"
}

variable "proxy_vpce_service_name" {
  type                    = string
  description             = "Specify the proxy server's VPC endpoint service name"
}

variable "proxy_listen_port" {
  type                    = number
  description             = "Specify the proxy server's listen port number"
}

/*
variable "gcp_proxy_server" {
  type                    = string 
  description             = "Hostname and port of proxy server to use for outbound GCP connections (e.g. proxy.example.com:8080)"
}
*/

# ----

variable "gcp_project_id" {
  type                    = string 
  description             = "GCP Project Id that Hub connects to"
}

variable "gcp_access_keyfile" {
  type                    = string 
  description             = "Full path to GCP credentials file"
}