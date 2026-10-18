#!/usr/bin/env bash
# Renova SOMENTE certificado NOVA, sem tocar em certificados de outros projetos.
set -Eeuo pipefail
DOMAIN=nova.gestaolojasonline.tech
CERT_PATH=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
[[ $(id -u) -eq 0 ]] || exit 1
[[ -f "$CERT_PATH" ]] || exit 1
before=$(stat -Lc %Y "$CERT_PATH")
docker run --rm --name nova-certbot-renew \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/lib/letsencrypt:/var/lib/letsencrypt \
  -v /var/www/nova-studio-acme:/var/www/nova-studio-acme \
  certbot/certbot:latest renew --cert-name "$DOMAIN" --non-interactive --quiet
after=$(stat -Lc %Y "$CERT_PATH")
if [[ "$before" != "$after" ]]; then
  nginx -t && systemctl reload nginx
fi
