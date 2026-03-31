terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "shopeasy-vpc-tf"
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_details" {
  value = aws_vpc.main
}
resource "aws_subnet" "public_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "shopeasy-public-1-tf"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "shopeasy-public-2-tf"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "shopeasy-private-1-tf"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "shopeasy-private-2-tf"
  }
}
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "shopeasy-igw-tf"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "shopeasy-public-rt-tf"
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}
resource "aws_security_group" "alb" {
  name   = "shopeasy-alb-sg-tf"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "shopeasy-alb-sg-tf" }
}

resource "aws_security_group" "ec2" {
  name   = "shopeasy-ec2-sg-tf"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "shopeasy-ec2-sg-tf" }
}
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "shopeasy" {
  key_name   = "shopeasy-key-tf"
  public_key = file("~/.ssh/shopeasy-key.pub")
}

resource "aws_instance" "user_service" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.shopeasy.key_name

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu
  EOF

  tags = {
    Name = "shopeasy-user-service-tf"
  }
}

output "ec2_public_ip" {
  value = aws_instance.user_service.public_ip
}

# Read existing ACM certificate (already created manually)
data "aws_acm_certificate" "zovie" {
  domain      = "zovie.app"
  statuses    = ["ISSUED"]
  most_recent = true
}

# RDS Security Group - only EC2 can connect on port 3306
resource "aws_security_group" "rds" {
  name        = "shopeasy-rds-sg-tf"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "shopeasy-rds-sg-tf" }
}

# RDS needs to know which subnets it can live in
resource "aws_db_subnet_group" "main" {
  name       = "shopeasy-db-subnet-group-tf"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = { Name = "shopeasy-db-subnet-group-tf" }
}

# RDS MySQL instance in private subnet
resource "aws_db_instance" "main" {
  identifier        = "shopeasy-db-dev-tf"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  skip_final_snapshot = true

  tags = { Name = "shopeasy-db-dev-tf" }
}

# Target Group - defines where ALB sends traffic
resource "aws_lb_target_group" "main" {
  name     = "shopeasy-tg-dev-tf"
  port     = 3001
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "shopeasy-tg-dev-tf" }
}

# ALB itself
resource "aws_lb" "main" {
  name               = "shopeasy-alb-dev-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = { Name = "shopeasy-alb-dev-tf" }
}

# Register EC2 into the target group
resource "aws_lb_target_group_attachment" "user_service" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.user_service.id
  port             = 3001
}

# HTTP listener - redirects to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener - forwards to target group
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.zovie.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

output "alb_dns" {
  value       = aws_lb.main.dns_name
  description = "Point dev.zovie.app CNAME to this in Cloudflare"
}

output "rds_endpoint" {
  value = split(":", aws_db_instance.main.endpoint)[0]
  description = "Use this as DB_HOST in GitHub Secrets"
}