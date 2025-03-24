# provider
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.92.0"
    }
    tls = {
      source = "hashicorp/tls"
      version = "4.0.6"
    }
  }
}

provider "aws" {
  # Configuration options
  region = "us-east-1"
}
#vpc
resource "aws_vpc" "kubeadm_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
tags = {
    name= "kubeadm_vpc"
    }

}

#subnet
resource "aws_subnet" "kubeadm_subnet" {
  vpc_id     = aws_vpc.kubeadm_vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "kubeadm_subnet"
  }
}

#igw
resource "aws_internet_gateway" "kubeadm_igw" {
  vpc_id = aws_vpc.kubeadm_vpc.id

  tags = {
    Name = "main"
  }
}
#route table
resource "aws_route_table" "kubeadm_route_table" {
  vpc_id = aws_vpc.kubeadm_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubeadm_igw.id
  }


  tags = {
    Name = "kubeadm_route_table"
  }
}

#associate igw with subnet
resource "aws_route_table_association" "kubeadm_rt_association" {
  subnet_id      = aws_subnet.kubeadm_subnet.id
  route_table_id = aws_route_table.kubeadm_route_table.id
}
#vpc_security group
resource "aws_security_group" "kubeadm_security_group" {
  name        = "kubeadm_security_group"
  tags = {
    name = "kubeadm_security_group"
  }


ingress {
  description = "Allow HTTPS"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

ingress {
  description = "Allow HTTP"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  }

  ingress {
  description = "Allow SSH"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  }
  egress  {
  to_port           = 0
  protocol          = "-1"
  prefix_list_ids   = [aws_vpc_endpoint.my_endpoint.prefix_list_id]
  from_port         = 0
  }
}

resource "aws_security_group" "kubeadm_control_plane" {
    name = "kubeadm_control_plane"
    tags = {
      name = "kubeadm_control_plane"
    }

ingress {
  description = "Kubernetes Server"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  }

ingress {
  description = "Kubelet Api"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  }

ingress {
  description = "kube-scheduler"
  from_port         = 10259
  to_port           = 10259
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  }

ingress {
  description = "kube-control-manager"
  from_port         = 10257
  to_port           = 10257
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  }

ingress {
  description = "etcd"
  from_port         = 2379
  to_port           = 2380
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "kubeadm_worker_node" {
    name = "kubeadm_worker_node"

ingress {
  description = "kublet api"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  }

ingress {
  description = "NodePort Services"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  }
  
}

resource "aws_security_group" "kubeadm_flannel" {
  name = "kubeam_flannel"

ingress {
  description = "Master-worker"
  from_port         = 8285
  to_port           = 8285
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  }
ingress {
  description = "Master-worker"
  from_port         = 8472
  to_port           = 8472
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  }

}


# instances reso
 #keypairs
resource "tls_private_key" "kubeadm_private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
  
  
  provisioner "local-exec" {
    command = "echo '${self.public_key_pem}' > ./pubkey.pem"
  }

}

resource "aws_key_pair"  "kubeadm_demo_keyp"{
  key_name = "gitopskey"
  public_key = tls_private_key.kubeadm_private_key.public_key_openssh
  
  provisioner "local-exec" {
    command = "echo '${tls_private_key.kubeadm_private_key.private_key_pem}' > ./privkey.pem"
  }
  
}

#control_plane instance

resource "aws_instance" "kubeadm_control_plane_instance" {
  ami           = var.kubeadm_ami_id
  instance_type = "t2.medium"
  key_name = aws_key_pair.kubeadm_demo_keyp.key_name
  associate_public_ip_address = true
  security_groups = [
    aws_security_group.kubeadm_control_plane,
    aws_aws_security_group.kubeadm_security_group,
    aws_security_group.kubeadm_flannel
  ]

  root_block_device {
    volume_size = 14
    volume_type = "gp2"
  }
  user_data = templatefile("./install-kubeadm.sh", {})
  tags = {
    Name = "kubeadm_control_plane_instance"
  }

  provisioner "local-exec" {
    command = "echo 'master ${self.public_ip}' >> ./files/hosts"
  }
}

resource "aws_instance" "kubeadm_worker_instance" {
    count = 2
    ami = var.kubeadm_ami_id
    instance_type = "t2.micro"
    key_name = aws_key_pair.kubeadm_demo_keyp.key_name
    associate_public_ip_address = true
    security_groups = [
    aws_security_group.kubeadm_worker_node,
    aws_aws_security_group.kubeadm_security_group,
    aws_security_group.kubeadm_flannel
    ]
    root_block_device {
    volume_size = 14
    volume_type = "gp2"
  }

    user_data = templatefile("./install-kubeadm-worker.sh", {})

    tags = {
    name = "kubeadm worker instance"
  } 

 

    provisioner "local-exec" {
    command = "echo 'worker-$(count.index) ${self.public_ip}' >> ./files/hosts"
  }
 
}