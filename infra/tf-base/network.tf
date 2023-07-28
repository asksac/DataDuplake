data "aws_vpc" "db_vpc" {
  id                      = var.db_vpc_id
}

data "aws_subnet" "db_subnet" {
  count                   = length(var.db_subnet_ids)
  id                      = var.db_subnet_ids[count.index]
}
