# security group to be used by database and glue objects (jobs/crawlers)
resource "aws_security_group" "app2_sg" {
  name                    = "${var.app_shortcode}_app2_sg"
  vpc_id                  = data.aws_vpc.app2_vpc.id

  ingress {
    self                  = true
    from_port             = 0
    to_port               = 0
    protocol              = "-1"
  }

  ingress {
    cidr_blocks           = [ data.aws_vpc.app2_vpc.cidr_block ]
    from_port             = 0
    to_port               = 0
    protocol              = "-1"
  }

  egress {
    from_port             = 0
    to_port               = 0
    protocol              = "-1"
    cidr_blocks           = [ "0.0.0.0/0" ]
  }
}

