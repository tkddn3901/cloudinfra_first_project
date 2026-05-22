import {
  to = aws_instance.bugTeam_db
  id = "i-024c2a9e885bf7012"
}

# 1. SSH 키 페어 (기존 키 조회)
data "aws_key_pair" "existing_kp_db" {
  key_name = "bugTeam-db-key"
}

# 2. 보안 그룹 (기존 SG 조회)
data "aws_security_group" "existing_sg_db" {
  id = "sg-08fc76d050ec4c1b0"
}

# 3. 최신 Ubuntu 24.04 AMI 조회
data "aws_ami" "ubuntu_db" {
  most_recent = true
  owners      = ["099720109477"] # Canonical 공식 ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# 4. DB 인스턴스 생성 및 안전 연동
resource "aws_instance" "bugTeam_db" {
  ami                    = data.aws_ami.ubuntu_db.id 
  instance_type          = var.instance_type 
  subnet_id              = aws_subnet.private_subnet["db"].id
  vpc_security_group_ids = [data.aws_security_group.existing_sg_db.id] 
  key_name               = data.aws_key_pair.existing_kp_db.key_name
  
  # Private Subnet이므로 공인 IP를 할당하지 않음
  associate_public_ip_address = false

  tags = {
    Name = "bugTeam-db"
  }

  lifecycle {
    ignore_changes = [
      ami,                     # 최신 AMI와 달라도 인스턴스 재생성 차단
      vpc_security_group_ids   # 보안 그룹 설정 차이로 인한 재생성 차단
    ]
  }
}

# 생성된 ec2의 private ip를 출력
output "instance_private_ip_db" {
    description = "만들어진 ec2의 private ipv4 주소"
    value       = aws_instance.bugTeam_db.private_ip
}