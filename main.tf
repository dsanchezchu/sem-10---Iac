provider "aws" {
  region = var.aws_region
}

# 1. Crear VPC y subredes
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public_1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"
  map_public_ip_on_launch = true
}

# 2. Internet Gateway y Route Table
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# 3. Security Group para permitir HTTP (80) y SSH (22)
resource "aws_security_group" "web_sg" {
  name        = "web-traffic"
  description = "Permitir HTTP y SSH"
  vpc_id      = aws_vpc.main.id

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
}

# 4. Crear 2 instancias EC2 (Nginx y Apache)
resource "aws_instance" "app1" {
  ami           = "ami-0c3ce86fb8321acb9" # Amazon Linux 2
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              sudo yum install nginx -y
              sudo systemctl start nginx
              sudo systemctl enable nginx
              echo "<h1>APP 1 (70% tráfico)</h1>" | sudo tee /usr/share/nginx/html/index.html
              EOF
  tags = {
    Name = var.app1_name
  }
}

resource "aws_instance" "app2" {
  ami           = "ami-0c3ce86fb8321acb9" # Amazon Linux 2
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public_2.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              sudo yum install httpd -y
              sudo systemctl start httpd
              sudo systemctl enable httpd
              echo "<h1>APP 2 (30% tráfico)</h1>" | sudo tee /var/www/html/index.html
              EOF
  tags = {
    Name = var.app2_name
  }
}

# 5. Application Load Balancer (ALB - ELBv2)
resource "aws_lb" "web_alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

# 6. Target Group para las instancias
resource "aws_lb_target_group" "web_tg" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# 7. Listener y regla 70-30
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Página no encontrada"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "app1_rule" {
  listener_arn = aws_lb_listener.web_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }

  condition {
    path_pattern {
      values = ["/app1*"]
    }
  }
}

resource "aws_lb_listener_rule" "app2_rule" {
  listener_arn = aws_lb_listener.web_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }

  condition {
    path_pattern {
      values = ["/app2*"]
    }
  }
}

# 8. Registrar instancias en el Target Group
resource "aws_lb_target_group_attachment" "app1_attach" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.app1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "app2_attach" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.app2.id
  port             = 80
}