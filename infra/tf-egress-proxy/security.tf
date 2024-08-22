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
    cidr_blocks             = concat([data.aws_vpc.vpc.cidr_block, "${local.my_ip}/32"], var.proxy_allowed_ingress_cidr_list) 
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


