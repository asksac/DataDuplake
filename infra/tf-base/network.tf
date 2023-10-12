## App2 VPC 

data "aws_vpc" "app2_vpc" {
  id                      = var.app2_vpc_id
}

data "aws_subnet" "app2_subnet" {
  count                   = length(var.app2_subnet_ids)
  id                      = var.app2_subnet_ids[count.index]
}

data "aws_route_tables" "app2_vpc_rts" {
  vpc_id                  = var.app2_vpc_id
}


## Hub VPC 
data "aws_vpc" "hub_vpc" {
  id                      = var.hub_vpc_id
}

data "aws_subnet" "hub_subnet" {
  count                   = length(var.hub_subnet_ids)
  id                      = var.hub_subnet_ids[count.index]
}

data "aws_route_tables" "hub_vpc_rts" {
  vpc_id                  = var.hub_vpc_id
}

