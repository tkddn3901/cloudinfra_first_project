# 1. SSH 키 페어 (기존 키 조회)
data "aws_key_pair" "existing_kp_gangnam" {
  key_name = "bugTeam-mgmt-key"
}

# 2. 보안 그룹 (기존 SG 조회)
data "aws_security_group" "existing_sg_gangnam" {
  id = "sg-0e1ee11c32922cd96"
}

# 3. Packer가 생성한 AMI 중 가장 최신 이미지를 가져오는 Data 소스
data "aws_ami" "latest_packer_web_gangnam" {
  most_recent = true
  owners      = ["self"] # 사용자가 직접 생성한 이미지만 검색

  filter {
    name   = "name"
    # Packer 설정 파일(ami_name)에 지정한 이름 규칙과 일치해야 합니다.
    values = ["ami-web-gangnam-*"] 
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# 4. ASG Launch Template
resource "aws_launch_template" "lt_gangnam" {
  name_prefix   = "bugTeam-asg-gangnam-"
  # 데이터 소스에서 가져온 최신 AMI ID를 자동으로 적용합니다.
  image_id      = "ami-0dc5df311e0453014"
  instance_type = var.instance_type
  
  # data 소스에서 가져온 ID와 Name을 사용하도록 수정
  vpc_security_group_ids = [data.aws_security_group.existing_sg_gangnam.id]
  key_name               = data.aws_key_pair.existing_kp_gangnam.key_name

  # 프로비저닝 후에 실행할 user_data 
  user_data = base64encode(<<-EOF
      #!/bin/bash
      cd /home/user1/gangnam

      # venv 활성화
      source venv/bin/activate

      # FastAPI 실행
      uvicorn api:app --host 0.0.0.0 --port 8000
    EOF
  )
  # default 버전을 항상 update 하도록 한다
  # ami 혹은 user_data 가 변경이 되었을때 default 버전을 변경하도록 한다 
  update_default_version = true

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "bugTeam-web-gangnam-asg" }
  }
}

# 5. Auto Scaling Group 정의
resource "aws_autoscaling_group" "asg_gangnam" {
  name = "bugTeam-asg-gangnam"
  # 서브넷 참조 방식 수정 (리스트 형태여야 함)
  vpc_zone_identifier = [aws_subnet.private_subnet["gangnam"].id]
  
  desired_capacity = var.desired_capacity
  max_size         = var.max_size
  min_size         = var.min_size

  target_group_arns = [aws_lb_target_group.tg_gangnam.arn]

  launch_template {
    id      = aws_launch_template.lt_gangnam.id
    version = aws_launch_template.lt_gangnam.latest_version
  }
}

# 6. ASG에 의해 생성된 실제 인스턴스의 정보를 조회
data "aws_instances" "asg_gangnam_nodes" {
  depends_on = [aws_autoscaling_group.asg_gangnam]

  instance_tags = {
    "aws:autoscaling:groupName" = aws_autoscaling_group.asg_gangnam.name
  }

  instance_state_names = ["running"]
}

# 7. 조회된 인스턴스 정보 출력
output "asg_gangnam_instance_ips" {
  description = "Auto Scaling Group 인스턴스들의 Private IP"
  value       = data.aws_instances.asg_gangnam_nodes.private_ips
}

# ==============================================================================
# 8. 동적 오토스케일링 정책 (강남구)
#
# 기준:
#   - avg_cgst <= 10  -> EC2 0대 (한적)
#   - 11 ~ 60         -> EC2 1대 (원활)
#   - 61 이상         -> EC2 2대 (혼잡)
#
# CloudWatch Metric:
#   namespace   = "cgst"
#   metric_name = "gangnam-cgst"
# ==============================================================================


# ==============================================================================
# [1] 확장 정책 (Scale-Out)
# 혼잡도가 10 초과 시 감시
# 11~60  → 1대
# 61 이상 → 2대
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "gangnam_cgst_high_alarm" {
  alarm_name          = "gangnam-cgst-high-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  period              = 300

  metric_name = "gangnam-cgst"
  namespace   = "cgst"
  statistic   = "Average"

  threshold = 10

  alarm_description = "Gangnam congestion > 10 (Scale-Out)"

  alarm_actions = [
    aws_autoscaling_policy.gangnam_cgst_scale_out_policy.arn
  ]
}

resource "aws_autoscaling_policy" "gangnam_cgst_scale_out_policy" {
  name                   = "gangnam-cgst-scale-out-policy"
  policy_type            = "StepScaling"
  autoscaling_group_name = aws_autoscaling_group.asg_gangnam.name
  adjustment_type        = "ExactCapacity"

  # StepScaling 에서는 cooldown 대신 estimated_instance_warmup 사용
  estimated_instance_warmup = 300

  # --------------------------------------------------
  # 11 ~ 60 → EC2 1대
  #
  # threshold=10 기준
  # diff = 1 ~ 50
  # 실제 metric = 11 ~ 60
  # --------------------------------------------------
  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 51
  }

  # --------------------------------------------------
  # 61 이상 → EC2 2대
  #
  # threshold=10 기준
  # diff >= 51
  # 실제 metric >= 61
  # --------------------------------------------------
  step_adjustment {
    scaling_adjustment          = 2
    metric_interval_lower_bound = 51
  }
}


# ==============================================================================
# [2] 축소 정책 (Scale-In)
# 혼잡도가 60 이하로 떨어질 때 감시
#
# 11~60  → 1대
# 10 이하 → 0대
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "gangnam_cgst_low_alarm" {
  alarm_name          = "gangnam-cgst-low-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  period              = 300

  metric_name = "gangnam-cgst"
  namespace   = "cgst"
  statistic   = "Average"

  threshold = 60

  alarm_description = "Gangnam congestion <= 60 (Scale-In)"

  alarm_actions = [
    aws_autoscaling_policy.gangnam_cgst_scale_in_policy.arn
  ]
}

resource "aws_autoscaling_policy" "gangnam_cgst_scale_in_policy" {
  name                   = "gangnam-cgst-scale-in-policy"
  policy_type            = "StepScaling"
  autoscaling_group_name = aws_autoscaling_group.asg_gangnam.name
  adjustment_type        = "ExactCapacity"

  # StepScaling 에서는 cooldown 대신 estimated_instance_warmup 사용
  estimated_instance_warmup = 300

  # --------------------------------------------------
  # 11 ~ 60 → EC2 1대
  #
  # threshold=60 기준
  # diff = -49 ~ 0
  # 실제 metric = 11 ~ 60
  # --------------------------------------------------
  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = -50
    metric_interval_upper_bound = 0
  }

  # --------------------------------------------------
  # 10 이하 → EC2 0대
  #
  # threshold=60 기준
  # diff <= -50
  # 실제 metric <= 10
  # --------------------------------------------------
  step_adjustment {
    scaling_adjustment          = 0
    metric_interval_upper_bound = -50
  }
}