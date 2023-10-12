
# 
# Security Group used for all VPC endpoints
#

resource "aws_security_group" "endpoint_sg" {
  name                        = "${var.app_shortcode}_endpoint_sg"
  vpc_id                      = data.aws_vpc.app2_vpc.id

  ingress {
    cidr_blocks               = [ data.aws_vpc.app2_vpc.cidr_block ]
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

  vpc_id                = data.aws_vpc.app2_vpc.id
  subnet_ids            = data.aws_subnet.app2_subnet[*].id
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

  vpc_id                = data.aws_vpc.app2_vpc.id
  subnet_ids            = data.aws_subnet.app2_subnet[*].id
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

  vpc_id                = data.aws_vpc.app2_vpc.id
  subnet_ids            = data.aws_subnet.app2_subnet[*].id
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

## Other VPC Endpoints required for Glue Jobs to run inside VPC

# com.amazonaws.region.secretsmanager: The endpoint for Secrets Manager service
resource "aws_vpc_endpoint" "vpce_secretsmgr" {
  service_name          = "com.amazonaws.${var.aws_region}.secretsmanager"

  vpc_id                = data.aws_vpc.app2_vpc.id
  subnet_ids            = data.aws_subnet.app2_subnet[*].id
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

resource "aws_vpc_endpoint" "vpce_cw_logs" {
  service_name          = "com.amazonaws.${var.aws_region}.logs"
  vpc_id                = data.aws_vpc.app2_vpc.id
  subnet_ids            = data.aws_subnet.app2_subnet[*].id
  private_dns_enabled   = true

  auto_accept           = true
  vpc_endpoint_type     = "Interface"

  security_group_ids    = [ aws_security_group.endpoint_sg.id ]

  policy                = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "CWLogsRequiredPermissions"
        Principal = "*"
        Action = [
          "logs:*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ] 
  })

  tags                  = {
    Name = "${var.app_name} - CloudWatch Logs VPC Endpoint"
  }
}

resource "aws_vpc_endpoint" "vpce_cw_metrics" {
  service_name          = "com.amazonaws.${var.aws_region}.monitoring"
  vpc_id                = data.aws_vpc.app2_vpc.id
  subnet_ids            = data.aws_subnet.app2_subnet[*].id
  private_dns_enabled   = true

  auto_accept           = true
  vpc_endpoint_type     = "Interface"

  security_group_ids    = [ aws_security_group.endpoint_sg.id ]

  policy                = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "CWRequiredPermissions"
        Principal = "*"
        Action = [
          "cloudwatch:*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ] 
  })

  tags                  = {
    Name = "${var.app_name} - CloudWatch Monitoring VPC Endpoint"
  }
}

resource "aws_vpc_endpoint" "vpce_glue_api" {
  service_name          = "com.amazonaws.${var.aws_region}.glue"
  vpc_id                = data.aws_vpc.app2_vpc.id
  subnet_ids            = data.aws_subnet.app2_subnet[*].id
  private_dns_enabled   = true

  auto_accept           = true
  vpc_endpoint_type     = "Interface"

  security_group_ids    = [ aws_security_group.endpoint_sg.id ]

  policy                = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "GlueRequiredPermissions"
        Principal = "*"
        Action = [
          "glue:*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ] 
  })

  tags                  = {
    Name = "${var.app_name} - Glue VPC Endpoint"
  }
}

resource "aws_vpc_endpoint" "vpce_kms" {
  service_name          = "com.amazonaws.${var.aws_region}.kms"
  vpc_id                = data.aws_vpc.app2_vpc.id
  subnet_ids            = data.aws_subnet.app2_subnet[*].id
  private_dns_enabled   = true

  auto_accept           = true
  vpc_endpoint_type     = "Interface"

  security_group_ids    = [ aws_security_group.endpoint_sg.id ]

  policy                = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "KmsRequiredPermissions"
        Principal = "*"
        Action = [
          "kms:*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ] 
  })

  tags                  = {
    Name = "${var.app_name} - KMS VPC Endpoint"
  }
}

resource "aws_vpc_endpoint" "vpce_s3_gateway" {
  service_name          = "com.amazonaws.${var.aws_region}.s3"
  vpc_id                = data.aws_vpc.app2_vpc.id
  route_table_ids       = data.aws_route_tables.app2_vpc_rts.ids

  auto_accept           = true
  vpc_endpoint_type     = "Gateway"

  policy                = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "FullAccess"
        Principal = "*"
        Action = [
          "s3:*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ] 
  })

  tags                  = {
    Name = "${var.app_name} - S3 Gateway Endpoint"
  }
}

