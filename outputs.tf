output "alb_dns_name" {
  description = "DNS del Load Balancer"
  value       = aws_lb.web_alb.dns_name
}