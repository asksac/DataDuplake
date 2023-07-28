# creates an application instance (EC2)

data "aws_ami" "ec2_ami" {
  most_recent             = true
  owners                  = ["amazon"]

  filter {  
    name                  = "name"
    values                = ["amzn2-ami-hvm-2*"]
  } 

  filter {  
    name                  = "architecture"
    values                = ["x86_64"]
  } 

  filter {  
    name                  = "root-device-type"
    values                = ["ebs"]
  } 

  filter {  
    name                  = "virtualization-type"
    values                = ["hvm"]
  } 
}

resource "aws_instance" "triage_instance" {
  ami                     = data.aws_ami.ec2_ami.id

  subnet_id               = data.aws_subnet.db_subnet[0].id
  vpc_security_group_ids  = [ aws_security_group.db_sg.id ]

  instance_type           = "t3.small"
  credit_specification {
    cpu_credits           = "standard"
  }
  iam_instance_profile    = aws_iam_instance_profile.ec2_instance_profile.name

  user_data               = <<EOF
#!/bin/bash -xe

yum update
yum install mysql
amazon-linux-extras install -y postgresql13

EOF

  tags                    = {
      Name = "${var.app_name} - Triage EC2 Instance"
  }
}

# -----
# IAM role for EC2 instance

resource "aws_iam_role" "ec2_exec_role" {
  name                      = "${var.app_shortcode}_ec2_exec_role" 
  path                      = "/"
  assume_role_policy        = jsonencode({
    Version                 = "2012-10-17",
    Statement               = [
      {  
        Action              = [ "sts:AssumeRole" ]
        Principal           = {
          Service           = "ec2.amazonaws.com"
        } 
        Effect              = "Allow"
        Sid                 = "EC2AssumeRolePolicy"
      }
    ]
  })
}

resource "aws_iam_policy" "ec2_exec_policy" {
  name                      = "${var.app_shortcode}_ec2_exec_policy"
  path                      = "/"
  description               = "IAM policy to grant required permissions to EC2"

  policy                    = jsonencode({
    Version         = "2012-10-17"
    Statement       = [
      {
        Sid = "SSMPermissions"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListInstanceAssociations", 
          "ssm:DescribeInstanceProperties", 
          "ssm:DescribeDocumentParameters", 
          "ssm:StartSession",
          "ssm:TerminateSession", 
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Sid = "SSMMessagesPermissions"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Sid = "EC2MessagesPermissions"
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
      {
        Action      = [
          "ec2:*",
        ]
        Resource    = "*"
        Effect      = "Allow"
        Sid         = "AllowFullEC2Access"
      }, 
      {
        "Effect": "Allow",
        "Action": [
          "kms:Encrypt", 
          "kms:Decrypt", 
          "kms:CreateGrant", 
          "kms:DescribeKey", 
          "kms:ListKeys", 
        ]
        Resource    = "*"
        Effect      = "Allow"
        Sid         = "AllowKMSAccess"
      }, 
      {
        Action      = [
          "logs:CreateLogGroup",
        ]
        Resource    = "arn:aws:logs:${var.aws_region}:${local.account_id}:*"
        Effect      = "Allow"
        Sid         = "AllowCloudWatchLogsAccess"
      }, 
      {
        Action      = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource    = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:*:*"
        Effect      = "Allow"
        Sid         = "AllowCloudWatchPutLogEvents"
      }, 
      {
        Action      = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource    = "arn:aws:s3:::*"
        Effect      = "Allow"
        Sid         = "AllowS3ReadWriteAccess"
      }, 
      {
        Action      = [
          "sns:Publish",
        ]
        Resource    = "arn:aws:sns:${var.aws_region}:${local.account_id}:*"
        Effect      = "Allow"
        Sid         = "AllowSNSPublishAccess"
      }, 
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_exec_policy_attachment" {
  role                      = aws_iam_role.ec2_exec_role.name
  policy_arn                = aws_iam_policy.ec2_exec_policy.arn
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name                      = "${var.app_shortcode}_ec2_instance_profile"
  role                      = aws_iam_role.ec2_exec_role.name
}
