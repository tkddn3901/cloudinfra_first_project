###############################
# VPC 생성
###############################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

###############################
# 인터넷 게이트웨이
###############################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

###############################
# AZ
###############################
data "aws_availability_zones" "available" {
  state = "available"
}

###############################
# 퍼블릭 서브넷 생성
###############################
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name = "${local.name_prefix}-public-gangnam"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = {
    Name = "${local.name_prefix}-public-eunpyeong"
  }
}

###############################
# 퍼블릭 라우팅 테이블
###############################
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${local.name_prefix}-public-route"
  }
}

resource "aws_route_table_association" "public_rt_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

###############################
# NAT 게이트웨이
###############################
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet_1.id
  tags = {
    Name = "${local.name_prefix}-nat-gw"
  }
}

###############################
# 프라이빗 앱 서브넷 (gangnam/eunpyeong, AZ 분리)
###############################
resource "aws_subnet" "private_app" {
  for_each = local.private_app_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = data.aws_availability_zones.available.names[each.value.az_index]

  tags = {
    Name = "${local.name_prefix}-private-app-${each.key}"
  }
}

###############################
# 프라이빗 DB 서브넷 (단일, for_each 에 포함하지 않아 중복 CIDR 생성 방지)
###############################
resource "aws_subnet" "private_subnet_db" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.db_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-subnet-db"
  }
}

###############################
# 프라이빗 라우팅 테이블
###############################
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = {
    Name = "${local.name_prefix}-private-route"
  }
}

resource "aws_route_table_association" "private_rt_assoc_app" {
  for_each = local.private_app_subnets

  subnet_id      = aws_subnet.private_app[each.key].id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_rt_assoc_db" {
  subnet_id      = aws_subnet.private_subnet_db.id
  route_table_id = aws_route_table.private_rt.id
}
