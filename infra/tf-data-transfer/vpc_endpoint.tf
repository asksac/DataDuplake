resource "aws_vpc_endpoint" "proxy_endpoint" {
  vpc_id                  = var.lambda_vpc_id
  service_name            = var.proxy_vpce_service_name
  vpc_endpoint_type       = "Interface"

  security_group_ids      = [ var.lambda_security_group_id ] 

  subnet_ids              = var.lambda_subnet_ids
  private_dns_enabled     = false
}
