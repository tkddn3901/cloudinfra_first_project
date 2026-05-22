variable "region" { default = "ap-northeast-2" }
variable "instance_type" { default = "t3.micro" }
variable "db_instance_type" { default = "t3.small" }
variable "ec2_user" { default = "ec2-user" }
variable "desired_capacity" { default = 3 }
variable "min_size" { default = 3 }
variable "max_size" { default = 4 }

data "aws_ami" "latest_web" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "name"
    # ami-web-{timestamp}
    values = ["ami-web-*"]
  }
}

# data "aws_key_pair" "existing_kp" { key_name = "bugTeam-mgmt-key" }