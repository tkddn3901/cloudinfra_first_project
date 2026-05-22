###############################
# Monitoring Server (Prometheus)
# - Public subnet 에 배치
# - Private subnet 의 ASG 인스턴스(Node Exporter :9100)를
#   EC2 Service Discovery 로 자동 수집
###############################

###############################
# 보안 그룹
###############################
resource "aws_security_group" "monitor_sg" {
  name        = "${local.name_prefix}-monitor-sg"
  description = "Prometheus monitoring server (public subnet)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Prometheus UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
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

  tags = {
    Name = "${local.name_prefix}-monitor-sg"
  }
}

###############################
# IAM (EC2 Service Discovery 용)
###############################
data "aws_iam_policy_document" "monitor_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitor_role" {
  name               = "${local.name_prefix}-monitor-role"
  assume_role_policy = data.aws_iam_policy_document.monitor_assume.json
}

data "aws_iam_policy_document" "monitor_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "ec2:DescribeRegions",
      "ec2:DescribeAvailabilityZones",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "monitor_policy" {
  name   = "${local.name_prefix}-monitor-policy"
  role   = aws_iam_role.monitor_role.id
  policy = data.aws_iam_policy_document.monitor_policy.json
}

resource "aws_iam_instance_profile" "monitor_profile" {
  name = "${local.name_prefix}-monitor-profile"
  role = aws_iam_role.monitor_role.name
}

###############################
# Monitoring EC2 인스턴스 (public subnet)
###############################
resource "aws_instance" "monitor" {
  ami                         = data.aws_ami.lastest_al2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnet_1.id
  vpc_security_group_ids      = [aws_security_group.monitor_sg.id]
  key_name                    = aws_key_pair.kp.key_name
  iam_instance_profile        = aws_iam_instance_profile.monitor_profile.name
  associate_public_ip_address = true

  # 부팅 시 Prometheus 자동 설치 & EC2 SD 설정 적용
  user_data = templatefile("${path.module}/monitor_user_data.sh.tftpl", {
    aws_region = var.region
  })
  # user_data 변경 시 인스턴스 교체 (그래야 스크립트가 다시 실행됨)
  user_data_replace_on_change = true

  tags = {
    Name = "${local.name_prefix}-monitor"
    Role = "monitor"
  }
}

###############################
# 고정 Public IP (EIP)
###############################
resource "aws_eip" "monitor_eip" {
  instance = aws_instance.monitor.id
  domain   = "vpc"
  tags = {
    Name = "${local.name_prefix}-monitor-eip"
  }
}

###############################
# 출력
###############################
output "monitor_public_ip" {
  description = "Prometheus UI: http://<monitor_public_ip>:9090"
  value       = aws_eip.monitor_eip.public_ip
}
