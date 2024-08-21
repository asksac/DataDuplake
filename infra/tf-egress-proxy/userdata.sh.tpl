#!/bin/bash -xe
#
# this is an ec2 user-data script (which runs as root during instance launch)
#
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

export AWS_REGION=${aws_region}
export AWS_ENV=${aws_env}

# update yum packages
dnf update -y

# install squid
dnf install -y squid
systemctl enable squid

# configure squid
sed -i 's/http_access deny all/http_access allow all/' /etc/squid/squid.conf
#echo 'acl allow_my_ip src {YOUR_IP}/32' | sudo tee -a /etc/squid/squid.conf

# restart squid
systemctl restart squid