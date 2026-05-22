#!/bin/bash

# Certbot 설치 스크립트
# cloudinfra.store 도메인에 SSL 인증서 자동 발급 및 갱신

DOMAIN="cloudinfra.store" # 도메인 고정

# Certbot 설치
echo "Certbot 설치 중..."
sudo dnf install -y certbot python3-certbot-nginx

# 인증서 발급
echo "SSL 인증서 발급 중..."
sudo certbot --nginx -d $DOMAIN

# 자동 갱신 설정
echo "자동 갱신 설정 중..."
echo "0 0 * * * root certbot renew --quiet" | sudo tee /etc/cron.d/certbot-renew

echo "완료! SSL 인증서가 발급되었습니다."