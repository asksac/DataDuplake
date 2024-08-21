# Using Amazon provided AMI
data "aws_ami" "ec2_ami" {
  most_recent           = true
  owners                = ["amazon"]

  filter {
    name                = "name"
    values              = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name                = "architecture"
    values              = ["x86_64"]
  }

  filter {
    name                = "root-device-type"
    values              = ["ebs"]
  }

  filter {
    name                = "virtualization-type"
    values              = ["hvm"]
  }
}


## Create EC2 IAM instance role and profile (execution role)

resource "aws_iam_role" "ec2_exec_role" {
  name                = "${lower(var.app_shortcode)}_ec2_exec_role"

  assume_role_policy  = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
  EOF
}

resource "aws_iam_role_policy" "ec2_exec_policy" {
  name                    = "${lower(var.app_shortcode)}_ec2_exec_policy"
  role                    = aws_iam_role.ec2_exec_role.id

  policy                  = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:*:*:*"
      ]
    }, 
    {
      "Effect": "Allow",
      "Action": [
        "s3:Get*"
      ],
      "Resource": [
        "arn:aws:s3:::*"
      ]
    }
  ]
}
EOF
}

data "aws_iam_policy" "AmazonSSMManagedInstanceCore" {
  name                      = "AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_exec_policy_ssm" {
  role                      = aws_iam_role.ec2_exec_role.id
  policy_arn                = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name                      = "${lower(var.app_shortcode)}_ec2_instance_profile"
  role                      = aws_iam_role.ec2_exec_role.name
}

# Load EC2 user-data script from template 
locals {
  ec2_userdata          = templatefile("${path.module}/userdata.sh.tpl", {
    app_shortcode           = var.app_shortcode
    aws_region              = var.aws_region
    aws_env                 = var.aws_env
  })
}

## App ASG ## 

resource "aws_launch_template" "proxy_launch_template" {
  name                      = "${lower(var.app_shortcode)}-app-launch-tpl"
  description               = "ProxyServer ASG Launch Template"

  image_id                  = data.aws_ami.ec2_ami.id
  instance_type             = var.ec2_instance_type

  user_data                 = base64encode(local.ec2_userdata)

  iam_instance_profile {
    name                    = aws_iam_instance_profile.ec2_instance_profile.name
  } 

  key_name                  = var.ssh_keypair_name
  vpc_security_group_ids    = [ aws_security_group.ec2_sg.id ]

  monitoring {
    enabled                 = true
  }

  lifecycle {
    create_before_destroy   = true
  }

  tag_specifications {
    resource_type           = "instance"
    tags                    = {
      Name                  = "${var.app_shortcode} ProxyServer"
      Application           = var.app_name 
      Environment           = var.aws_env
    }
  }
}

resource "aws_autoscaling_group" "proxy_asg" {
  name                      = "${lower(var.app_shortcode)}-app-asg"

  min_size                  = 1
  max_size                  = 2
  desired_capacity          = 1

  health_check_type         = "EC2"
  vpc_zone_identifier       = data.aws_subnet.pub_subnets.*.id

  launch_template {
    id                      = aws_launch_template.proxy_launch_template.id
    version                 = "$Latest"
  }

  metrics_granularity       = "1Minute"
  enabled_metrics           = ["GroupDesiredCapacity", "GroupInServiceInstances"]

  target_group_arns         = [ 
    aws_lb_target_group.proxy_nlb_tg.arn 
  ]

  lifecycle {
    create_before_destroy   = true
    ignore_changes          = [ desired_capacity ]
  }
}

data "aws_instances" "proxy_instances" {
  instance_tags           = tomap({
    "Name": "${var.app_shortcode} ProxyServer", 
    "aws:autoscaling:groupName": aws_autoscaling_group.proxy_asg.name, 
  })
  instance_state_names    = ["running", "pending"]
}

data "aws_instance" "proxy_instance_1" {
  instance_id             = tolist(data.aws_instances.proxy_instances.ids)[0]
}
