# 1. Route 53 에 호스팅 영역에 등록된 도메인 정보 조회
data "aws_route53_zone" "selected" {
    name = "${var.domain_name}." # 뒤에 반드시 . 을 붙여줘야 한다.
    private_zone = false # public 영역의 도메인이기 때문데
}

# 2. ACM 인증서 발급 신청
resource "aws_acm_certificate" "cert" {
  domain_name       = "*.${var.domain_name}" # 서브도메인용
  validation_method = "DNS"
  # 루트 도메인도 함께 보호
  subject_alternative_names = [var.domain_name]
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name = "bugTeam-certificate"
  }
}

# 3. DNS 검증용 레코드 생성
resource "aws_route53_record" "cert_validation" {
  # 인증서의 도메인 검증 옵션들을 반복문돌면서 하나씩 꺼내서 map 그로로 변환
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }


  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selected.zone_id
}


# 4. 인증서 검증 대기 및 완료 (최종 상태 확인)
# 이 리소스가 성공적으로 완료되면 콘솔에서 '발급됨(Issued)' 상태를 볼 수 있습니다.
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}


# 5. 발급된 인증서의 arn 확인(출력)
output "certificate_arn" {
  value = aws_acm_certificate_validation.cert.certificate_arn
}