import {
  to = aws_instance.bugTeam_eunpyeong
  id = "i-0cb9812cb4037829d"
}

# 1. SSH 키 페어 (기존 키 조회)
data "aws_key_pair" "existing_kp_default_eunpyeong" {
  key_name = "bugTeam-eunpyeong-key"
}

# 2. 보안 그룹 (기존 SG 조회)
data "aws_security_group" "existing_sg_default_eunpyeong" {
  id = "sg-08fc76d050ec4c1b0"
}

# 3. 최신 Ubuntu 24.04 AMI 조회
data "aws_ami" "latest_rocky" {
  most_recent = true

  owners = ["679593333241"]

  filter {
    name   = "name"
    values = ["Rocky-9-EC2-Base-9*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 4. DB 인스턴스 생성
resource "aws_instance" "bugTeam_eunpyeong" {
  ami           = data.aws_ami.latest_rocky.id 
  instance_type = var.eunpyeong_instance_type
  subnet_id     = aws_subnet.private_subnet["eunpyeong"].id
  vpc_security_group_ids = [data.aws_security_group.existing_sg_default_eunpyeong.id] 
  key_name      = data.aws_key_pair.existing_kp_default_eunpyeong.key_name
  
  # Private Subnet이므로 공인 IP를 할당하지 않음
  associate_public_ip_address = false

  tags = {
    Name = "bugTeam-web-eunpyeong"
  }

  lifecycle {
    ignore_changes = [
      ami,
      vpc_security_group_ids
    ]
  }
}

# 생성된 ec2의 private ip를 출력
output "instance_private_ip_eunpyeong" {
    description = "만들어진 ec2의 private ipv4 주소"
    value       = aws_instance.bugTeam_eunpyeong.private_ip
}