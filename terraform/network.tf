# test08_autoscale/network.tf

# vpc, subnet, 보안그룹 등의 network에 관련된 자원 정의

import {
  to = aws_vpc.main
  id = "vpc-0c30872af87fc15d0"
}

import {
  to = aws_internet_gateway.igw
  id = "igw-0ff38ac2314d2046f"
}

import {
  to = aws_subnet.public_subnet
  id = "subnet-06d9aab265f849080"
}

import {
  to = aws_subnet.public_subnet2
  id = "subnet-0f3f4100ecf519e86"
}

import {
  to = aws_route_table_association.public_assoc2
  id = "subnet-0f3f4100ecf519e86/rtb-0c67c33073a1749fd"
}

import {
  to = aws_subnet.private_subnet["gangnam"]
  id = "subnet-05c68388cbfcb1e91"
}

import {
  to = aws_subnet.private_subnet["eunpyeong"]
  id = "subnet-009ba05c79df489a7"
}

import {
  to = aws_subnet.private_subnet["db"]
  id = "subnet-008805911e903e453"
}

import {
  to = aws_route_table.public_rt
  id = "rtb-0c67c33073a1749fd"
}

import {
  to = aws_route_table.private_rt
  id = "rtb-0a0d86001bda6a027"
}

import {
  to = aws_route_table_association.public_assoc1
  id = "subnet-06d9aab265f849080/rtb-0c67c33073a1749fd"
}

# gangnam 서브넷 연결 임포트
import {
  to = aws_route_table_association.private_assoc["gangnam"]
  id = "subnet-05c68388cbfcb1e91/rtb-0a0d86001bda6a027"
}

# eunpyeong 서브넷 연결 임포트
import {
  to = aws_route_table_association.private_assoc["eunpyeong"]
  id = "subnet-009ba05c79df489a7/rtb-0a0d86001bda6a027"
}

# db 서브넷 연결 임포트
import {
  to = aws_route_table_association.private_assoc["db"]
  id = "subnet-008805911e903e453/rtb-0a0d86001bda6a027"
}

# NAT 게이트웨이용 EIP 임포트
import {
  to = aws_eip.nat_eip
  id = "eipalloc-01e5ffca15efd4928" # 실제 EIP 할당 ID
}

# NAT 게이트웨이 임포트
import {
  to = aws_nat_gateway.nat_gw
  id = "nat-09c7ee698ea6c60de" # 실제 NAT 게이트웨이 ID
}

# VPC 생성
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "bugTeam-vpc" }
}

# 인터넷 게이트웨이
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "bugTeam-igw" }
}

# 퍼블릭 서브넷1
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.avail_zone_1
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet" }
}

# 퍼블릭 서브넷2
resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = var.avail_zone_2
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet2" }
}

# 퍼블릭 라우팅 테이블
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "bugTeam-public-route" }
}

# 라우팅 테이블을 subnet에 연결하기
resource "aws_route_table_association" "public_assoc1" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# 라우팅 테이블을 subnet에 연결하기
resource "aws_route_table_association" "public_assoc2" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public_rt.id
}

# 프라이빗 서브넷
locals {
  private_subnets = {
    gangnam   = "10.0.2.0/28"
    eunpyeong = "10.0.2.16/28"
    db        = "10.0.3.0/24"
  }
}

resource "aws_subnet" "private_subnet" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = var.avail_zone_1

  tags = {
    Name = "private-subnet-${each.key}"
  }
}

# NAT 게이트웨이가 사용할 탄력적 IP
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = { Name = "bugTeam-nat-eip" }
}

# NAT 게이트웨이 (보통 퍼블릭 서브넷에 위치해야 합니다)
resource "aws_nat_gateway" "nat_gw" {
    allocation_id = aws_eip.nat_eip.id
    subnet_id     = aws_subnet.public_subnet.id # 퍼블릭 서브넷 ID

    tags = { Name = "bugTeam-nat-gw" }

    # IGW가 생성된 후에 NAT GW가 생성되도록 의존성 명시
    depends_on = [aws_internet_gateway.igw]
}

# 프라이빗 라우팅 테이블
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = { Name = "bugTeam-private-route" }
}

# 프라이빗 라우팅 테이블을 private_subnet에 연결하기
resource "aws_route_table_association" "private_assoc" {
    for_each = local.private_subnets

    subnet_id      = aws_subnet.private_subnet[each.key].id
    route_table_id = aws_route_table.private_rt.id
}
