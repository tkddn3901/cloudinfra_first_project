import {
  to = aws_instance.bugTeam_mgmt
  id = "i-0733b8d678268066c"
}

# 1. SSH 키 페어 (기존 키 조회)
data "aws_key_pair" "existing_kp_mgmt" {
  key_name = "bugTeam-mgmt-key"
}

# 2. 보안 그룹 (기존 SG 조회)
data "aws_security_group" "existing_sg_mgmt" {
  id = "sg-0eaedf5965a2a31ab"
}

# 4. MGMT 인스턴스 설정 (기존 인스턴스 유지)
resource "aws_instance" "bugTeam_mgmt" {
  ami           = "ami-0d4c056a16f3ae150" 
  instance_type = var.mgmt_instance_type
  subnet_id     = aws_subnet.public_subnet.id
  
  vpc_security_group_ids = [data.aws_security_group.existing_sg_mgmt.id] 
  key_name               = data.aws_key_pair.existing_kp_mgmt.key_name
  
  # 고정 EIP를 붙일 것이므로 인스턴스 자체의 임시 퍼블릭 IP 할당 옵션은 true 상태로 둡니다.
  associate_public_ip_address = true

  tags = {
    Name = "bugTeam-mgmt"
  }

  lifecycle {
    ignore_changes = [
      ami,
      vpc_security_group_ids
    ]
  }
}

# 5. 기존에 생성되어 있는 Elastic IP(EIP) 조회
data "aws_eip" "existing_eip_mgmt" {
  id = "eipalloc-0509ce7bd8b4f8967" 
}

# 6. 기존 EIP와 EC2 인스턴스 연결 매핑
resource "aws_eip_association" "mgmt_eip_assoc" {
  instance_id   = aws_instance.bugTeam_mgmt.id
  allocation_id = data.aws_eip.existing_eip_mgmt.id
}

# 생성된 ec2의 퍼블릭 IP 출력 (이제 고정 IP 주소가 출력됩니다)
output "instance_public_ip_mgmt" {
    description = "MGMT 인스턴스의 고정 Elastic IP 주소"
    value       = data.aws_eip.existing_eip_mgmt.public_ip
}