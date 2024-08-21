## VPC 
data "aws_vpc" "vpc" {
  id                      = var.vpc_id
}

data "aws_subnet" "pub_subnets" {
  count                   = length(var.subnet_ids)
  id                      = var.subnet_ids[count.index]
}

data "aws_route_tables" "vpc_rts" {
  vpc_id                  = var.vpc_id
}

