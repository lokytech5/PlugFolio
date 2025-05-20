terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.97.0"
    }
  }
  backend "s3" {}
}
# PlugFolio Terraform configuration
provider "aws" {
  region = var.aws_region
}

#VPC and Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "plugfolio-vpc"
  }
}

# Subnets, Internet Gateway, and Route Table
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name = "plugfolio-public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "plugfolio-igw"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "plugfolio-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id

}

# Security Groups
resource "aws_security_group" "plugfolio_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "plugfolio-sg"
  description = "Allow HTTP, SSH access"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "plugfolio-security-group"
  }

}

# EC2 Instance
resource "aws_instance" "plugfolio_instance" {
  ami                    = "ami-084568db4383264d4"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.plugfolio_sg.id]
  user_data = templatefile("../scripts/user-data.sh.tmpl", {
    my_app_service = file("../services/plugfolio-app.service")
  })
  key_name                    = data.aws_key_pair.existing.key_name
  associate_public_ip_address = true
  tags = {
    Name = "plugfolio-instance"
  }
}

#Fetch existing Route 53 Hosted Zone
data "aws_route53_zone" "main" {
  name         = var.root_domain
  private_zone = false
}

#Fetch existing Key Pair from AWS
data "aws_key_pair" "existing" {
  key_name = "ec2-login-key"
}

#EBS Volume for EC2
resource "aws_ebs_volume" "plugfolio_volume" {
  availability_zone = aws_instance.plugfolio_instance.availability_zone
  size              = 30
  type              = "gp2"
  tags = {
    Name = "plugfolio-ebs-volume"
  }
}

resource "aws_volume_attachment" "plugfolio_volume_attachment" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.plugfolio_volume.id
  instance_id = aws_instance.plugfolio_instance.id

}

data "aws_iam_role" "plugfolio_lambda_role" {
  name = "PlugfolioLambdaRole"
}

data "aws_iam_role" "plugfolio_codebuild_role" {
  name = "PlugfolioCodeBuildRole"
}

data "aws_iam_role" "plugfolio_ssm_role" {
  name = "PlugfolioSSMRole"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

# S3 Bucket for Scr
resource "aws_s3_bucket" "plugfolio_scripts" {
  bucket = "plugfolio-scripts${random_string.suffix.result}"
  tags = {
    Name = "PlugfolioScriptsBucket"
  }

}

resource "aws_s3_object" "deploy_app_script" {
  bucket       = aws_s3_bucket.plugfolio_scripts.bucket
  key          = "deploy-app.sh"
  source       = "${path.module}/../scripts/deploy-app.sh"
  etag         = filemd5("${path.module}/../scripts/deploy-app.sh")
  content_type = "text/x-shellscript"
  acl          = "private"
}
