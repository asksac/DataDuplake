output "proxy_instance_public_dns" {
  value                     = data.aws_instance.proxy_instance_1.public_dns
}

output "proxy_nlb_ssh_fqdn" {
  value                     = aws_lb.proxy_nlb.dns_name 
}

output "ssh_command" {
  value                     = "ssh -i ${var.ssh_private_key_file} ec2-user@${data.aws_instance.proxy_instance_1.public_dns}"
}

output "proxy_test_command" {
  value                     = "curl --proxy http://${aws_lb.proxy_nlb.dns_name}:${var.proxy_port} ipinfo.io"
}

output "proxy_vpc_endpoint_service" {
  value                     = aws_vpc_endpoint_service.proxy_nlb_vpces.service_name
}