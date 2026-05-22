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

source "amazon-ebs" "web_image" {
    ami_name        = "ami-web-{{timestamp}}"
    instance_type   = "t3.micro" 
    region          = "ap-northeast-2"
    source_ami      = "ami-0b6cacee0430cdb2c"  # amazon linux 최신 AMI
    ssh_username    = "ec2-user"
}

build {
    sources = ["source.amazon-ebs.web_image"]
    provisioner "ansible" {
        playbook_file   = "./site.yml"
        user            = "ec2-user"
        use_proxy       = false
        galaxy_file     = "./requirements.yml"
    }
}