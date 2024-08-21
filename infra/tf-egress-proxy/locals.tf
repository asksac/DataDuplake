data "aws_caller_identity" "current" {}

data "http" "ip" {
  url                     = "https://ifconfig.me/ip"
}

locals {
  account_id              = data.aws_caller_identity.current.account_id

  # Common tags to be assigned to all resources
  common_tags             = {
    Application           = var.app_name 
    Environment           = var.aws_env
  }

  my_ip                   = data.http.ip.response_body

  squid_listen_port       = 3128
}
