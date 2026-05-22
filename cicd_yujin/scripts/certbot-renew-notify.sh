#!/bin/bash
source /home/user5/.env

DOMAIN="cloudinfra.store"

# 인증서 갱신
certbot renew --quiet

# 남은 일수 확인
EXPIRY=$(openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
DAYS_LEFT=$(( ( $(date -d "${EXPIRY}" +%s) - $(date +%s) ) / 86400 ))

# 텔레그램 알림
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d text="🔐 SSL 인증서 갱신 완료! ${DOMAIN} - 남은 기간: ${DAYS_LEFT}일"