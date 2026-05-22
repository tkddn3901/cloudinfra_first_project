# test08_autoscale/variables.tf

# 변수 정의 
variable "region" { default = "ap-northeast-2" }
variable "instance_type" { default = "t3.micro" }
variable "eunpyeong_instance_type" { default = "t3.small" }
variable "mgmt_instance_type" { default = "m7i-flex.large" }
# autoscaling 그룹에서 원하는 ec2의 갯수
variable "desired_capacity" { default = 0 }
# autoscaling 그룹에서 최소 ec2의 갯수
variable "min_size" { default = 0 }
# autoscaling 그룹에서 최대 ec2의 갯수
variable "max_size" { default = 2 }
# 첫번째 가용영역
variable "avail_zone_1" { default = "ap-northeast-2a" }
# 두번째 가용영역
variable "avail_zone_2" { default = "ap-northeast-2c" }
# domain
variable "domain_name" { default = "gmfrd.store" }