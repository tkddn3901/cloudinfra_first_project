packer {
    required_plugins {
        amazon = {
            version = ">= 1.2.8"
            source  = "github.com/hashicorp/amazon"
        }
        ansible = {
            version = ">= 1.1.0"
            source  = "github.com/hashicorp/ansible"
        }
    }
}

# 새 인스턴스를 임시로 띄워서 빌드하는 표준 ebs 방식
source "amazon-ebs" "web_image_eunpyeong" {
    ami_name      = "ami-web-eunpyeong-{{timestamp}}"
    region        = "ap-northeast-2"
    instance_type = "t3.small"  # 임시 빌드용 사양
    ssh_username  = "rocky"
    
    # [필수 수정] 기존 인스턴스 ID 대신, 그 인스턴스의 원본 AMI ID를 넣어야 합니다.
    source_ami    = "ami-06b18c6a9a323f75f" 
    
    # 임시 인스턴스가 생성될 VPC의 서브넷 ID (인터넷 통신이 가능해야 함)
    # subnet_id   = "	subnet-06d9aab265f849080" 
}

build {
    sources = ["source.amazon-ebs.web_image_eunpyeong"]

    provisioner "ansible" {
        playbook_file   = "./site.yml"
        user            = "rocky"
        use_proxy       = false
        galaxy_file     = "./requirements.yml"
    }
}