
# 
# Security Group used for all VPC endpoints
#

resource "aws_security_group" "endpoint_sg" {
  name                        = "${var.app_shortcode}_endpoint_sg"
  vpc_id                      = data.aws_vpc.db_vpc.id

  ingress {
    cidr_blocks               = [ data.aws_vpc.db_vpc.cidr_block ]
    from_port                 = 443
    to_port                   = 443
    protocol                  = "tcp"
  }

  tags                    = {
      Name = "${var.app_name} - VPC Endpoint SG"
  }
}


## VPC Endpoint to AWS Services required by SSM Session Manager ##

# com.amazonaws.region.ssm: The endpoint for the Systems Manager service
resource "aws_vpc_endpoint" "vpce_ssm" {
  service_name          = "com.amazonaws.${var.aws_region}.ssm"

  vpc_id                = data.aws_vpc.db_vpc.id
  subnet_ids            = data.aws_subnet.db_subnet[*].id
  private_dns_enabled   = true

  auto_accept           = true
  vpc_endpoint_type     = "Interface"

  security_group_ids    = [ aws_security_group.endpoint_sg.id ]

  policy                = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "SSMRequiredPermissions"
        Principal = "*"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListInstanceAssociations", 
          "ssm:DescribeInstanceProperties", 
          "ssm:DescribeDocumentParameters", 
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]        
  })

  tags                    = {
      Name = "${var.app_name} - SSM VPC Endpoint"
  }
}

# com.amazonaws.region.ec2messages: Systems Manager uses this endpoint to make calls from SSM Agent to the Systems Manager service
resource "aws_vpc_endpoint" "vpce_ec2_messages" {
  service_name          = "com.amazonaws.${var.aws_region}.ec2messages"

  vpc_id                = data.aws_vpc.db_vpc.id
  subnet_ids            = data.aws_subnet.db_subnet[*].id
  private_dns_enabled   = true

  auto_accept           = true
  vpc_endpoint_type     = "Interface"

  security_group_ids    = [ aws_security_group.endpoint_sg.id ]

  policy                = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "SSMRequiredPermissions"
        Principal = "*"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]        
  })

  tags                    = {
      Name = "${var.app_name} - EC2Messages VPC Endpoint"
  }
}

# com.amazonaws.region.ssmmessages: This endpoint is required to connect to your instances through a secure data channel using Session Manager 
resource "aws_vpc_endpoint" "vpce_ssm_messages" {
  service_name          = "com.amazonaws.${var.aws_region}.ssmmessages"

  vpc_id                = data.aws_vpc.db_vpc.id
  subnet_ids            = data.aws_subnet.db_subnet[*].id
  private_dns_enabled   = true

  auto_accept           = true
  vpc_endpoint_type     = "Interface"

  security_group_ids    = [ aws_security_group.endpoint_sg.id ]

  policy                = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "SSMRequiredPermissions"
        Principal = "*"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]        
  })

  tags                    = {
      Name = "${var.app_name} - SSMMessages VPC Endpoint"
  }
}

# com.amazonaws.region.secretsmanager: The endpoint for Secrets Manager service
resource "aws_vpc_endpoint" "vpce_secretsmgr" {
  service_name          = "com.amazonaws.${var.aws_region}.secretsmanager"

  vpc_id                = data.aws_vpc.db_vpc.id
  subnet_ids            = data.aws_subnet.db_subnet[*].id
  private_dns_enabled   = true

  auto_accept           = true
  vpc_endpoint_type     = "Interface"

  security_group_ids    = [ aws_security_group.endpoint_sg.id ]

  policy                = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "SecretsManagerRequiredPermissions"
        Principal = {
          AWS = local.account_id
        }
        Action = [
          "secretsmanager:*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]        
  })

  tags                    = {
      Name = "${var.app_name} - SecretsManager VPC Endpoint"
  }
}
