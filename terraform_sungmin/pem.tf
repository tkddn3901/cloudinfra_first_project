############################################
# create pem file
############################################
# 알고리즘 설정
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
# 키등록
resource "aws_key_pair" "kp" {
  key_name   = local.key_pair_name
  public_key = tls_private_key.pk.public_key_openssh
}
# 개인키 가져오기
# resource "local_file" "ssh_key" {
#   filename        = "${local.ansible_inventory}/${local.pem_key_name}.pem"
#   content         = tls_private_key.pk.private_key_pem
#   file_permission = "0600"
# }