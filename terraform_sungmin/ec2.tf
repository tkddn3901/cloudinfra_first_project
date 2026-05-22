###############################
# EC2 인스턴스 생성
###############################
data "aws_ami" "lastest_al2023" {
    most_recent = true
    owners = ["amazon"]
    filter {
        name = "name"
        values = ["al2023-ami-*-x86_64"]
    }
}

resource "aws_instance" "db_server" {
    ami = data.aws_ami.latest_web.id
    instance_type = var.db_instance_type
    subnet_id = aws_subnet.private_subnet_db.id
    vpc_security_group_ids = [aws_security_group.db_sg.id]
    key_name = aws_key_pair.kp.key_name
    tags = {
        Name = "${local.name_prefix}-db-server"
    }
}