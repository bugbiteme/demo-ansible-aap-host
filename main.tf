provider "aws" {
  region = var.region
}

// Generate the SSH keypair that we’ll use to configure the EC2 instance. 
// After that, write the private key to a local file and upload the public key to AWS

resource "tls_private_key" "key" {
  algorithm = "RSA"
}

resource "local_file" "private_key" {
  filename = "${path.module}/ec2-rhel-aap-key.pem"
  //sensitive_content = tls_private_key.key.private_key_pem
  content         = tls_private_key.key.private_key_pem
  file_permission = "0400"
}


resource "aws_key_pair" "key_pair" {
  key_name   = local_file.private_key.filename
  public_key = tls_private_key.key.public_key_openssh
}


// Create a security group with access to port 22 and port 80 open to serve HTTP traffic

data "aws_vpc" "default" {
  default = true
}


resource "aws_security_group" "sg_aap" {
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "AAP Controller"
  }
}

// Get latest Ubuntu AMI, so that we can configure the EC2 instance

data "aws_ami" "rhel" {
  most_recent = true

  owners = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-9.1*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

}

// Configure the EC2 instance itself

resource "aws_instance" "ec2_instance" {
  count                       = var.instances
  ami                         = data.aws_ami.rhel.id
  //associate_public_ip_address = true
  instance_type               = "t3.xlarge" #req for AAP
  vpc_security_group_ids      = [aws_security_group.sg_aap.id]
  key_name                    = aws_key_pair.key_pair.key_name


  # Storage specifications
  root_block_device {
    volume_size = 60 # req for AAP
  }

  tags = {
    Name = "AAP Controller"
  }

}

#assign static public IP
resource "aws_eip_association" "public_ip" {
  instance_id   = aws_instance.ec2_instance[0].id
  allocation_id = "eipalloc-077f6cecdfb662298"
}

#creating ansible inventory file
resource "local_file" "ansible_inventory" {
  filename = "inventory"
  content  = join("\n", aws_instance.ec2_instance[*].public_ip)
}

// Output the public_ip and the Ansible command to connect to ec2 instance

output "ec2_instance_ip" {
  description = "IP address of the EC2 instance"
  //value       = aws_instance.ec2_instance[0].public_ip
  value = join("\n", aws_instance.ec2_instance[*].public_ip)
}

output "ec2_instance_public_dns" {
  description = "DNS name of the EC2 instance"
  //value       = aws_instance.ec2_instance[0].public_dns
  value = join("\n", aws_instance.ec2_instance[*].public_dns)
}

output "connection_string" {
  description = "Copy/Paste/Enter - You are in the matrix for first instance"
  value       = "ssh -i ${path.module}/ec2-rhel-aap-key.pem ${var.ec2_username}@${aws_instance.ec2_instance[0].public_dns}"
}


