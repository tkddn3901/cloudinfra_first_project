# 로드 밸런서 (ALB) 보안 그룹
resource "aws_security_group" "alb_sg" {
  name        = "bugTeam-alb-sg"
  vpc_id      = aws_vpc.main.id

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
}

# 로드 밸런서 본체 정의
resource "aws_lb" "web_alb" {
  name               = "bugTeam-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet.id, aws_subnet.public_subnet2.id] 
}

# 강남용 대상 그룹
resource "aws_lb_target_group" "tg_gangnam" {
  name     = "tg-gangnam"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# 은평용 대상 그룹
resource "aws_lb_target_group" "tg_eunpyeong" {
  name     = "tg-eunpyeong"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

# ALB HTTP 리스너 (HTTPS로 강제 리다이렉트)
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
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

# ALB HTTPS 리스너의 Default Action
resource "aws_lb_listener" "web_listener_https" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Access Denied or Invalid Path"
      status_code  = "403"
    }
  }
}

# www.도메인 연결
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = aws_lb.web_alb.dns_name
    zone_id                = aws_lb.web_alb.zone_id
    evaluate_target_health = true
  }
}

# 루트(root) 도메인 연결
resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain_name
  type    = "A"
  
  alias {
    name                   = aws_lb.web_alb.dns_name
    zone_id                = aws_lb.web_alb.zone_id
    evaluate_target_health = true
  }
}

# ALB 리스너 규칙 (HTTPS 리스너로 바인딩 변경)
resource "aws_lb_listener_rule" "routing_gangnam" {
  listener_arn = aws_lb_listener.web_listener_https.arn # 변경됨
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_gangnam.arn
  }

  condition {
    path_pattern {
      values = [
        "/gangnam/*",
        "/gangnam"
      ]
    }
  }
}

resource "aws_lb_listener_rule" "routing_eunpyeong" {
  listener_arn = aws_lb_listener.web_listener_https.arn # 변경됨
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_eunpyeong.arn
  }

  condition {
    path_pattern {
      values = [
        "/eunpyeong/*",
        "/eunpyeong"
      ]
    }
  }
}

output "alb_dns_name" {
  description = "여기로 접속하세요!"
  value       = aws_lb.web_alb.dns_name
}
