variable "aws_region" {
  description = "Región de AWS"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  default     = "t2.micro"
}

variable "app1_name" {
  description = "Nombre de la App 1 (70% tráfico)"
  default     = "nginx-app"
}

variable "app2_name" {
  description = "Nombre de la App 2 (30% tráfico)"
  default     = "apache-app"
}