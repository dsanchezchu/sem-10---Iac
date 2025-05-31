provider "aws" {
  region = var.aws_region
}

# 0. Create SSH key pair for instance access
resource "aws_key_pair" "app_key_pair" {
  key_name   = "app-access-key"
  public_key = file("~/.ssh/app_key.pub")  # Make sure to generate this key using ssh-keygen
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
  key_name      = aws_key_pair.app_key_pair.key_name
  user_data     = <<-EOF
              #!/bin/bash
              
              # Enable detailed logging
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
              
              echo "Starting user data script execution..."
              
              # Install Nginx
              echo "Installing Nginx..."
              # Wait for any existing yum processes to finish
              while pgrep -f "yum" > /dev/null; do
                  echo "Waiting for other yum processes to complete..."
                  sleep 5
              done
              
              # Clean yum cache and enable nginx1
              sudo yum clean all
              echo "Enabling nginx1 repository..."
              sudo amazon-linux-extras enable nginx1
              sudo yum -y clean metadata
              echo "Installing nginx package (not nginx1)..."
              sudo yum -y install nginx
              
              if [ $? -ne 0 ]; then
                echo "Failed to install Nginx"
                echo "Checking available packages in the nginx1 repository:"
                sudo yum list available nginx*
                exit 1
              fi
              
              # Verify nginx was installed correctly
              echo "Verifying nginx installation..."
              rpm -qa | grep nginx
              
              # Create directory and content
              echo "Creating web content directories..."
              sudo mkdir -p /usr/share/nginx/html/app1
              echo "<h1>APP 1 (70% trafico)</h1>" | sudo tee /usr/share/nginx/html/app1/index.html
              echo "OK" | sudo tee /usr/share/nginx/html/app1/health.html
              
              # Configure Nginx
              echo "Configuring Nginx..."
              sudo tee /etc/nginx/nginx.conf <<'EOL'
              user nginx;
              worker_processes auto;
              error_log /var/log/nginx/error.log debug; # Enhanced error logging level
              pid /run/nginx.pid;
              
              events {
                  worker_connections 1024;
              }
              
              http {
                  include             /etc/nginx/mime.types;
                  default_type        application/octet-stream;
                  
                  server {
                      listen       80 default_server;
                      server_name  _;
                      root         /usr/share/nginx/html;
                      
                      location /app1/ {
                          alias /usr/share/nginx/html/app1/;
                          index index.html;
                          access_log /var/log/nginx/app1_access.log;
                          error_log /var/log/nginx/app1_error.log debug;
                      }
                      
                      location = /app1/health.html {
                          alias /usr/share/nginx/html/app1/health.html;
                          access_log /var/log/nginx/health_access.log;
                          error_log /var/log/nginx/health_error.log debug;
                      }
                      
                      error_page 404 /404.html;
                  }
              }
              EOL
              
              # Set permissions
              echo "Setting file permissions..."
              sudo chown -R nginx:nginx /usr/share/nginx/html
              sudo chmod -R 755 /usr/share/nginx/html
              
              # Start Nginx
              echo "Starting Nginx..."
              sudo systemctl enable nginx
              sudo systemctl start nginx
              
              # Test the configuration
              echo "Testing Nginx configuration..."
              sudo nginx -t
              
              # Verify nginx service status
              echo "Checking Nginx service status..."
              sudo systemctl status nginx
              
              # Wait a moment for Nginx to start
              sleep 5
              
              # Test local access
              echo "Testing local access..."
              curl -v http://localhost/app1/health.html
              if [ $? -ne 0 ]; then
                echo "Failed to access health check endpoint"
                echo "Checking nginx error logs:"
                sudo cat /var/log/nginx/error.log
                sudo cat /var/log/nginx/app1_error.log
                sudo cat /var/log/nginx/health_error.log
                sudo nginx -t
                echo "Checking if port 80 is listening:"
                sudo netstat -tlnp | grep :80
                echo "Checking SELinux status:"
                getenforce
              else
                echo "Health check endpoint is accessible"
              fi
              
              # List the contents of the app1 directory to verify files
              echo "Contents of /usr/share/nginx/html/app1:"
              ls -la /usr/share/nginx/html/app1/
              
              # Verify the health.html file has correct content and permissions
              echo "Checking health.html content and permissions:"
              cat /usr/share/nginx/html/app1/health.html
              ls -la /usr/share/nginx/html/app1/health.html
              
              echo "User data script completed."
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
  key_name      = aws_key_pair.app_key_pair.key_name
  user_data = <<-EOF
              #!/bin/bash
              # Enable logging
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
              
              echo "Starting user data script execution..."
              
              # Install Apache
              echo "Installing Apache..."
              sudo yum install httpd -y
              
              # Create directories and content
              echo "Creating web content..."
              sudo mkdir -p /var/www/html/app2
              echo "<h1>APP 2 (30% trafico)</h1>" | sudo tee /var/www/html/app2/index.html
              echo "OK" | sudo tee /var/www/html/app2/health.html
              
              # Configure Apache
              echo "Configuring Apache..."
              sudo tee /etc/httpd/conf.d/app2.conf <<'EOL'
              <Directory "/var/www/html/app2">
                  Require all granted
              </Directory>
              
              Alias /app2 "/var/www/html/app2"
              EOL
              
              # Set permissions
              echo "Setting permissions..."
              sudo chown -R apache:apache /var/www/html
              sudo chmod -R 755 /var/www/html
              
              # Start Apache
              echo "Starting Apache..."
              sudo systemctl start httpd
              sudo systemctl enable httpd
              
              # Test local access
              echo "Testing local access..."
              curl -v http://localhost/app2/health.html
              
              echo "User data script completed."
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

# 6. Target Groups para las instancias
# Target Group for APP1 (Nginx)
resource "aws_lb_target_group" "app1_tg" {
  name     = "app1-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/app1/health.html"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 10
    matcher             = "200"  # Only accept 200 OK responses
  }
}

# Target Group for APP2 (Apache)
resource "aws_lb_target_group" "app2_tg" {
  name     = "app2-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/app2/health.html"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200,302,404"  # More lenient matching
  }
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
    target_group_arn = aws_lb_target_group.app1_tg.arn
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
    target_group_arn = aws_lb_target_group.app2_tg.arn
  }

  condition {
    path_pattern {
      values = ["/app2*"]
    }
  }
}

# 8. Registrar instancias en el Target Group
resource "aws_lb_target_group_attachment" "app1_attach" {
  target_group_arn = aws_lb_target_group.app1_tg.arn
  target_id        = aws_instance.app1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "app2_attach" {
  target_group_arn = aws_lb_target_group.app2_tg.arn
  target_id        = aws_instance.app2.id
  port             = 80
}
