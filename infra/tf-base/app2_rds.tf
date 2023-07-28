##
## RDS Aurora Database Setup
##

resource "aws_db_subnet_group" "db_subnet_group" {
  name                    = "${var.app_shortcode}-aurora-subnet-group"
  subnet_ids              = data.aws_subnet.db_subnet[*].id

  tags                    = {
      Name = "${var.app_name} Aurora DB Subnet Grp"
  }
}

resource "aws_security_group" "db_sg" {
  name                    = "${var.app_shortcode}_db_sg"
  vpc_id                  = data.aws_vpc.db_vpc.id

  ingress {
    self                  = true
    from_port             = 0
    to_port               = 0
    protocol              = "-1"
  }

  ingress {
    cidr_blocks           = [ data.aws_vpc.db_vpc.cidr_block ]
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

resource "aws_rds_cluster" "aurora_serverless_v1" {
  cluster_identifier      = "${var.app_shortcode}-aurora-sl-mysql"
  engine                  = "aurora-mysql" # uses latest supported mysql version
  engine_mode             = "serverless"

  database_name           = var.db_name
  master_username         = var.db_master_user
  master_password         = random_password.rds_master_password.result # var.db_master_pass
  #manage_master_user_password = true # Aurora Serverless v1 does not support this
  # output secrets arn = aws_rds_cluster.aurora_serverless_v1.master_user_secret.secret_arn
  
  scaling_configuration {
    auto_pause               = false
    max_capacity             = 16
    min_capacity             = 1
    seconds_until_auto_pause = 300
    timeout_action           = "ForceApplyCapacityChange"
  }

  #availability_zones      = [ for i in range(var.az_count): data.aws_availability_zones.available_azs.names[i] ]

  lifecycle {
    ignore_changes        = [ master_password, availability_zones ]
  }

  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  port                    = 3306
  vpc_security_group_ids  = [ aws_security_group.db_sg.id ]  

  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"
  final_snapshot_identifier = "${var.app_shortcode}-aurora-sl-mysql-backup"
  skip_final_snapshot     = true

  tags                    = {
      Name = "${var.app_name} - Aurora Serverless v1 MySQL"
  }
}

/*
resource "aws_rds_cluster" "aurora_serverless_v2" {
  cluster_identifier      = "${var.app_shortcode}-aurora-sl-mysql"
  engine                  = "aurora-mysql" # uses latest supported mysql version
  engine_mode             = "provisioned"

  database_name           = var.db_name
  master_username         = var.db_master_user
  master_password         = random_password.new_random_password.result # var.db_master_pass

  serverlessv2_scaling_configuration {
    max_capacity          = 1.0
    min_capacity          = 0.5
  }
  
  #availability_zones      = [ for i in range(var.az_count): data.aws_availability_zones.available_azs.names[i] ]

  lifecycle {
    ignore_changes        = [ master_password, availability_zones ]
  }

  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  port                    = 3306
  vpc_security_group_ids  = [ aws_security_group.db_sg.id ]  

  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"
  final_snapshot_identifier = "${var.app_shortcode}-aurora-sl-mysql-backup"
  skip_final_snapshot     = true

  tags                    = {
      Name = "${var.app_name} Aurora Serverless MySQL"
  }
}
*/

## this resource is used to generate a new random password during each run
## password from output may be used in tfvars file for subsequent runs
## terraform apply -target random_password.new_random_password -auto-approve

resource "random_password" "rds_master_password" {
  length                  = 16
  special                 = true
  override_special        = "_%#$"

  lifecycle {
    create_before_destroy = true
  }
}
