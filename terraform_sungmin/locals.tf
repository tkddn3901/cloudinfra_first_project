locals {
  name_prefix   = "bugTeam"
  key_pair_name = "bugTeam-mgmt-key"

  # 앱 계층: AZ별로 분리된 프라이빗 서브넷 (퍼블릭 10.0.1.0/24, 10.0.2.0/24 와 비겹치 CIDR 사용)
  private_app_subnets = {
    gangnam = {
      cidr_block = "10.0.10.0/24"
      az_index   = 0 # public_subnet_1 과 동일 AZ
    }
    eunpyeong = {
      cidr_block = "10.0.11.0/24"
      az_index   = 1 # public_subnet_2 과 동일 AZ
    }
  }

  db_subnet_cidr = "10.0.20.0/24"
}
