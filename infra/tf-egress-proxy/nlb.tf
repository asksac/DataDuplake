resource "aws_security_group" "ec2_sg" {
  name                      = "${lower(var.app_shortcode)}-ec2-sg"
  vpc_id                    = data.aws_vpc.vpc.id

  ingress {
    cidr_blocks             = concat([data.aws_vpc.vpc.cidr_block, "${local.my_ip}/32"], var.proxy_allowed_ingress_cidr_list) 
    from_port               = local.squid_listen_port
    to_port                 = local.squid_listen_port
    protocol                = "tcp"
  }

  ingress {
    cidr_blocks             = [data.aws_vpc.vpc.cidr_block, "${local.my_ip}/32"]
    from_port               = 22
    to_port                 = 22
    protocol                = "tcp"
  }

  # squid proxy instances should be able to connect to all Internet destinations
  egress {
    from_port               = 0
    to_port                 = 0
    protocol                = "-1"
    cidr_blocks             = [ "0.0.0.0/0" ]
  }
}

resource "aws_security_group" "nlb_sg" {
  name                      = "${lower(var.app_shortcode)}-nlb-sg"
  vpc_id                    = data.aws_vpc.vpc.id

  ingress {
    cidr_blocks             = concat(["${local.my_ip}/32"], var.proxy_allowed_ingress_cidr_list) 
    from_port               = var.proxy_port
    to_port                 = var.proxy_port
    protocol                = "tcp"
    description             = "SSH"
  }

  egress {
    from_port               = local.squid_listen_port
    to_port                 = local.squid_listen_port
    protocol                = "tcp"
    cidr_blocks             = [ data.aws_vpc.vpc.cidr_block ]
  }
}


resource "aws_lb" "proxy_nlb" {
  name                      = "${lower(var.app_shortcode)}-proxy-nlb"
  internal                  = false
  load_balancer_type        = "network"
  security_groups           = [ aws_security_group.nlb_sg.id ]

  subnets                   = data.aws_subnet.pub_subnets.*.id 
  enable_cross_zone_load_balancing  = true
  
  lifecycle {
    create_before_destroy   = true
  }
}

resource "aws_lb_listener" "proxy_nlb_listener" {
  load_balancer_arn         = aws_lb.proxy_nlb.arn
  port                      = var.proxy_port 
  protocol                  = "TCP"

  default_action {
    type                    = "forward"
    target_group_arn        = aws_lb_target_group.proxy_nlb_tg.arn
  }
}

resource "aws_lb_target_group" "proxy_nlb_tg" {
  name                      = "${lower(var.app_shortcode)}-proxy-tg"
  port                      = local.squid_listen_port # inbound port at target
  protocol                  = "TCP"
  target_type               = "instance" # Auto Scaling requires target type to be instance
  preserve_client_ip        = true
  vpc_id                    = data.aws_vpc.vpc.id

  health_check {
    enabled                 = true 
    port                    = "traffic-port"
    protocol                = "TCP"
  }

  lifecycle {
    ignore_changes          = [  ]
  }
}

resource "aws_lb_listener" "proxy_nlb_ssh_listener" {
  load_balancer_arn         = aws_lb.proxy_nlb.arn
  port                      = var.ssh_ingress_port # inbound port of NLB
  protocol                  = "TCP"

  default_action {
    type                    = "forward"
    target_group_arn        = aws_lb_target_group.proxy_nlb_ssh_tg.arn
  }
}

resource "aws_lb_target_group" "proxy_nlb_ssh_tg" {
  name                      = "${lower(var.app_shortcode)}-proxy-ssh-tg"
  port                      = 22 # inbound port at target
  protocol                  = "TCP"
  target_type               = "instance" # Auto Scaling requires target type to be instance
  preserve_client_ip        = true
  vpc_id                    = data.aws_vpc.vpc.id
}
