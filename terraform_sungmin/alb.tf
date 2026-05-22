###############################
# 로드 밸런서 (ALB)
###############################
resource "aws_lb" "web_alb" {
    name               = "${local.name_prefix}-web-alb"
    internal           = false
    load_balancer_type = "application"
    security_groups    = [aws_security_group.alb_sg.id]
    subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
    tags = {
        Name = "${local.name_prefix}-web-alb"
    }
}

resource "aws_lb_target_group" "tg_gangnam" {
    name     = "tg-gangnam"
    port     = 80
    protocol = "HTTP"
    vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group" "tg_eunpyeong" {
    name     = "tg-eunpyeong"
    port     = 80
    protocol = "HTTP"
    vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "web_listener" {
    load_balancer_arn = aws_lb.web_alb.arn
    port              = "80"
    protocol          = "HTTP"

    default_action {
        type = "fixed-response"
        fixed_response {
            content_type = "text/plain"
            message_body = "404: Not Found"
            status_code  = "404"
        }
    }
}

resource "aws_lb_listener_rule" "routing_gangnam" {
    listener_arn = aws_lb_listener.web_listener.arn
    priority     = 10

    action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.tg_gangnam.arn
    }

    condition {
        path_pattern {
            values = ["/gangnam/*"]
        }
    }
}

resource "aws_lb_listener_rule" "routing_eunpyeong" {
    listener_arn = aws_lb_listener.web_listener.arn
    priority     = 20

    action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.tg_eunpyeong.arn
    }

    condition {
        path_pattern {
            values = ["/eunpyeong/*"]
        }
    }
}