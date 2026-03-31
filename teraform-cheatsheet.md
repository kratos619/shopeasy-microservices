# ⚡ Terraform Cheat Sheet
> Infrastructure as Code — Write once, deploy everywhere

---

## 🧠 The Mental Model

```
You write HCL code
      ↓
terraform plan    → Preview (nothing changes in AWS)
      ↓
terraform apply   → AWS creates real resources
      ↓
terraform destroy → AWS deletes everything
```

> **Golden Rule:** Never click in AWS console for things Terraform manages.
> If you click, Terraform won't know — that's called **drift**.

---

## 📁 File Structure

```
project/
├── main.tf           ← All your resources live here
├── variables.tf      ← Variable declarations (name, type, default)
├── terraform.tfvars  ← Actual secret values (NEVER commit this)
├── outputs.tf        ← Values printed after apply
├── .gitignore        ← Must exclude: *.tfstate, terraform.tfvars
├── .terraform/       ← Provider plugins (auto-generated, don't touch)
└── terraform.tfstate ← Terraform's memory (never manually edit)
```

---

## 🔧 Core Commands

| Command | What it does |
|---|---|
| `terraform init` | Download provider plugins (like `npm install`) |
| `terraform validate` | Check syntax — catches errors before plan |
| `terraform plan` | Preview changes. **Always run before apply.** |
| `terraform apply` | Create/update real AWS resources |
| `terraform destroy` | Delete everything Terraform created |
| `terraform output` | Print output values after apply |
| `terraform state list` | See everything Terraform is tracking |
| `terraform fmt` | Auto-format your HCL code |

---

## 🏗️ The Three Block Types

### `resource` — Creates things in AWS
```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c6a8bbb64f907189"
  instance_type = "t2.micro"
  tags = { Name = "my-server" }
}
```

### `data` — Reads existing things (doesn't create)
```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}
```

### `output` — Prints values after apply
```hcl
output "ec2_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Use this to SSH"
}
```

---

## 📦 Variables

### Declare in `variables.tf`
```hcl
variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true   # Hides value from terminal output
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"   # Optional default
}
```

### Provide values in `terraform.tfvars`
```hcl
db_password   = "MySecurePass2026!!"
instance_type = "t3.micro"
```

### Use variables in `main.tf`
```hcl
resource "aws_db_instance" "main" {
  password      = var.db_password
  instance_class = var.instance_type
}
```

---

## 🔗 Resource References (No Hardcoding)

```hcl
# BAD — hardcoded ID
resource "aws_instance" "web" {
  subnet_id = "subnet-abc123"   # ❌ Never do this
}

# GOOD — reference by resource
resource "aws_instance" "web" {
  subnet_id = aws_subnet.public_1.id   # ✅ Terraform resolves order automatically
}
```

> Terraform automatically figures out creation order from references.
> If EC2 references a subnet, it creates subnet first, then EC2.

---

## 🛡️ Security Groups — Chaining Pattern

```hcl
# ALB security group
resource "aws_security_group" "alb" {
  name   = "my-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # Internet can hit ALB
  }
}

# EC2 security group — only ALB can reach port 3001
resource "aws_security_group" "ec2" {
  name   = "my-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]   # ← Chaining
  }
}

# RDS security group — only EC2 can reach port 3306
resource "aws_security_group" "rds" {
  name   = "my-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]   # ← Chaining
  }
}
```

---

## 🌐 Complete VPC Pattern

```hcl
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "my-vpc" }
}

# Public subnets (EC2, ALB live here)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
}

# Private subnets (RDS lives here — no internet access)
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-south-1a"
}

# Internet Gateway — the door to the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Route table — what makes a subnet "public"
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}
```

---

## 🗄️ RDS Pattern

```hcl
# Subnet group — tells RDS which subnets it can use
resource "aws_db_subnet_group" "main" {
  name       = "my-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_db_instance" "main" {
  identifier        = "my-db"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false   # Never true in production
  skip_final_snapshot = true    # DEV only — set false in prod
}
```

---

## ⚖️ ALB Pattern

```hcl
# Target group — where traffic goes
resource "aws_lb_target_group" "main" {
  name     = "my-tg"
  port     = 3001
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/health"
  }
}

# The ALB itself
resource "aws_lb" "main" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# Register EC2 in target group
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.web.id
  port             = 3001
}

# HTTP → redirect to HTTPS
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

# HTTPS → forward to target group
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
```

---

## 💡 Common `data` Sources

```hcl
# Latest Ubuntu AMI (never hardcode AMI IDs)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical — always specify for security
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# Existing ACM certificate
data "aws_acm_certificate" "main" {
  domain      = "yourdomain.com"   # Must match exact domain on cert
  statuses    = ["ISSUED"]
  most_recent = true
}
```

---

## 🔑 EC2 with Docker Auto-Install

```hcl
resource "aws_key_pair" "main" {
  key_name   = "my-key"
  public_key = file("~/.ssh/my-key.pub")   # Generate with: ssh-keygen -t ed25519
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.main.key_name

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu
  EOF

  tags = { Name = "my-server" }
}
```

---

## ⚠️ Hard-Won Lessons

| Problem | Root Cause | Fix |
|---|---|---|
| `Access denied for user` | Password contains `$`, `@`, `/` or `"` | Use only letters + numbers + `!` in passwords |
| `empty result` on `data` block | Wrong domain or region | Check exact domain/ARN matches what's in AWS |
| GitHub Actions can't read secrets | Job has `environment: DEV` — reads only from DEV environment secrets | Move secrets to correct environment, not repo level |
| Terraform creates duplicate resources | You manually created in console first | Delete manual resource, then `terraform apply` |
| RDS deletion hangs | Waiting for snapshot or multi-AZ failover | Check `skip_final_snapshot = true` for dev |
| `terraform apply` modifies unexpected resources | Someone manually changed AWS console | That's drift — Terraform corrects it back |

---

## 🚫 .gitignore (Always Include)

```gitignore
.terraform/
*.tfstate
*.tfstate.backup
terraform.tfvars
*.tfvars
```

---

## 🔄 Rebuild Entire Stack from Scratch

```bash
cd your-terraform-dir/

terraform init        # Download providers
terraform validate    # Check for errors
terraform plan        # Review what will be created
terraform apply       # Create everything (~5 min)

# Grab outputs
terraform output ec2_public_ip
terraform output alb_dns
terraform output rds_endpoint

# Update these after every apply:
# 1. EC2_DEV_IP → GitHub repo secret
# 2. dev CNAME  → Cloudflare DNS record
```

---

## 📊 resource vs data — Quick Reference

| | `resource` | `data` |
|---|---|---|
| **Does** | Creates/manages AWS resource | Reads existing AWS resource |
| **Example** | `resource "aws_vpc" "main"` | `data "aws_ami" "ubuntu"` |
| **Reference** | `aws_vpc.main.id` | `data.aws_ami.ubuntu.id` |
| **On destroy** | Deletes the resource | Does nothing |
| **Use when** | You own it | Someone else created it |

---

*Last updated: March 2026 | ShopEasy Project | Gaurav Pal*