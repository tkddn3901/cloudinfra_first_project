import {
  to = aws_instance.bugTeam_gangnam
  id = "i-04034bb923a93fc86"
}

# 1. SSH 키 페어 (기존 키 조회)
data "aws_key_pair" "existing_kp_default_gangnam" {
  key_name = "bugTeam-gangnam-key"
}

# 2. 보안 그룹 (기존 SG 조회)
data "aws_security_group" "existing_sg_default_gangnam" {
  id = "sg-08fc76d050ec4c1b0"
}

# 3. 최신 Ubuntu 24.04 AMI 조회
data "aws_ami" "ubuntu_gangnam" {
  most_recent = true
  owners      = ["099720109477"] # Canonical 공식 ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# 4. 강남 인스턴스 연동 및 유지
resource "aws_instance" "bugTeam_gangnam" {
  ami                    = data.aws_ami.ubuntu_gangnam.id
  instance_type          = var.instance_type 
  subnet_id              = aws_subnet.private_subnet["gangnam"].id
  vpc_security_group_ids = [data.aws_security_group.existing_sg_default_gangnam.id] 
  key_name               = data.aws_key_pair.existing_kp_default_gangnam.key_name
  
  associate_public_ip_address = false

  tags = {
    Name = "bugTeam-web-gangnam"
  }

  lifecycle {
    ignore_changes = [
      ami,
      vpc_security_group_ids
    ]
  }
}

# 생성된 ec2의 private ip를 출력
output "instance_private_ip_gangnam" {
    description = "만들어진 ec2의 private ipv4 주소"
    value       = aws_instance.bugTeam_gangnam.private_ip
}