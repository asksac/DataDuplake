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

resource "aws_vpc_endpoint_service" "proxy_nlb_vpces" {
  acceptance_required        = false
  network_load_balancer_arns = [ aws_lb.proxy_nlb.arn ]
}
