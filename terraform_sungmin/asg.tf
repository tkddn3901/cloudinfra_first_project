###############################
# ASG gangnam / eunpyeong — AZ별 프라이빗 앱 서브넷에 배치
###############################
resource "aws_launch_template" "lt" {
  name_prefix   = "${local.name_prefix}-lt"
  image_id = data.aws_ami.latest_web.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  key_name = aws_key_pair.kp.key_name

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-app"
      Role = "web"
    }
  }
}

resource "aws_autoscaling_group" "asg_gangnam" {
  name             = "${local.name_prefix}-asg-gangnam"
  vpc_zone_identifier = [aws_subnet.private_app["gangnam"].id]

  desired_capacity = var.desired_capacity
  max_size         = var.max_size
  min_size         = var.min_size

  target_group_arns = [aws_lb_target_group.tg_gangnam.arn]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_group" "asg_eunpyeong" {
  name             = "${local.name_prefix}-asg-eunpyeong"
  vpc_zone_identifier = [aws_subnet.private_app["eunpyeong"].id]

  desired_capacity = var.desired_capacity
  max_size         = var.max_size
  min_size         = var.min_size

  target_group_arns = [aws_lb_target_group.tg_eunpyeong.arn]

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
}
