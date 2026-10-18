#!/usr/bin/env bash
# NOVA Studio: publica somente nova.gestaolojasonline.tech, mantendo os outros vhosts.
set -Eeuo pipefail
umask 022
DOMAIN=nova.gestaolojasonline.tech
REPO_BASE=/opt/nova-studio
NGINX_CONF=/etc/nginx/conf.d/nova-studio.conf
ACME_ROOT=/var/www/nova-studio-acme
CERT_ROOT=/etc/letsencrypt
CERT_NAME=nova.gestaolojasonline.tech
DOCKER_CERTBOT_IMAGE=certbot/certbot:latest
CONF_CREATED=0
SUCCESS=0
fail() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }
rollback() {
  if [[ "$CONF_CREATED" == 1 && "$SUCCESS" != 1 ]]; then
    echo 'Instalação HTTPS não concluída; restaurando a configuração anterior do Nginx.' >&2
    rm -f "$NGINX_CONF"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  fi
}
trap rollback EXIT
[[ $(id -u) -eq 0 ]] || fail 'Execute com sudo ou root.'
for cmd in nginx docker curl awk getent systemctl openssl ss python3; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Ferramenta necessária não encontrada: $cmd"
done
[[ -d "$REPO_BASE/.git" ]] || fail 'Instalação /opt/nova-studio não foi encontrada.'
[[ ! -e "$NGINX_CONF" ]] || fail 'A configuração nova-studio.conf já existe. Não sobrescrevemos configurações existentes.'
[[ ! -e "$CERT_ROOT/live/$CERT_NAME" ]] || fail 'Já existe certificado para o NOVA. Revisão manual é necessária para evitar mudanças inesperadas.'
[[ -f "$REPO_BASE/.env" ]] || fail 'Arquivo de chave NOVA não encontrado.'
nginx -t >/dev/null 2>&1 || fail 'O Nginx já apresenta falhas; nenhum ajuste foi feito.'
nginx -T 2>/dev/null | grep -E '^[[:space:]]*include[[:space:]]+/etc/nginx/conf\.d/\*\.conf;' >/dev/null || fail 'Nginx não inclui conf.d/*.conf. Verificar layout antes de publicar.'
if nginx -T 2>/dev/null | grep -E 'server_name[[:space:]]+nova\.gestaolojasonline\.tech' >/dev/null; then fail 'Já existe um vhost para NOVA. Nenhuma alteração efetuada.'; fi
[[ $(curl -fsS --max-time 5 'http://127.0.0.1:8018/live') == *'"ok":true'* ]] || fail 'O NOVA não respondeu na porta local 8018.'
http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 'http://127.0.0.1:8018/api/v1/projects')
[[ "$http_code" == 401 ]] || fail "A API não está protegida (HTTP $http_code)."

# DNS-only: Cloudflare com proxy desativado durante emissão, para validar IPv4 real.
EXPECTED_IP=$(curl -4fsS --max-time 7 'https://api.ipify.org') || fail 'Não foi possível consultar o IPv4 público de saída.'
[[ "$EXPECTED_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail 'IPv4 público inesperado.'
DNS_IPS=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u) || true
if [[ -z "$DNS_IPS" ]]; then
  echo 'Resolvedor local ainda não reconhece NOVA; verificando DNS público do Google (somente leitura).'
  DNS_IPS=$(curl -fsS --max-time 12 "https://dns.google/resolve?name=${DOMAIN}&type=A" | python3 -c 'import json,sys
d=json.load(sys.stdin)
a=d.get("Answer",[]) if d.get("Status")==0 else []
print(" ".join(sorted({r.get("data","") for r in a if r.get("type")==1 and r.get("name","").rstrip(".").lower()=="nova.gestaolojasonline.tech"})))') || fail 'Falha ao consultar DNS público de forma segura.'
  [[ -n "$DNS_IPS" ]] || fail 'DNS público não possui registro A válido para NOVA.'
fi
[[ "$DNS_IPS" == "$EXPECTED_IP" ]] || fail "DNS atual ($DNS_IPS) diferente do IPv4 público de saída ($EXPECTED_IP). Confira o IP de entrada no hPanel e deixe Cloudflare em DNS only."
if [[ -e "$REPO_BASE/.hosting-dns-confirmed" ]]; then
  echo 'Marcador local de DNS encontrado.'
else
  echo "DNS resolve para $EXPECTED_IP. Confirme que é o IPv4 da VPS no painel Hostinger."
fi

install -d -m 0755 "$ACME_ROOT/.well-known/acme-challenge"
cat > "$ACME_ROOT/.well-known/acme-challenge/nova-probe" <<'EOF'
nova-acme-probe
EOF
chmod 644 "$ACME_ROOT/.well-known/acme-challenge/nova-probe"

# Primeira fase: responder SOMENTE o desafio, sem publicar a API por HTTP.
TMP_CONF=$(mktemp /etc/nginx/conf.d/.nova-studio.XXXXXXXX)
cat > "$TMP_CONF" <<'EOF'
server {
    listen 80;
    server_name nova.gestaolojasonline.tech;
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/nova-studio-acme;
        default_type text/plain;
        try_files $uri =404;
    }
    location / { return 404; }
}
EOF
chmod 644 "$TMP_CONF"
mv "$TMP_CONF" "$NGINX_CONF"
CONF_CREATED=1
nginx -t || fail 'Nova configuração HTTP não passou em nginx -t.'
nginx -T 2>/dev/null | grep -F 'server_name nova.gestaolojasonline.tech;' >/dev/null || fail 'Novo vhost não está incluído na configuração efetiva do Nginx.'
systemctl reload nginx || fail 'Não foi possível recarregar o Nginx.'

# systemctl reload pode terminar antes de os workers novos aceitarem conexões.
# A verificação anterior falhava imediatamente, quando o vhost antigo ainda respondia 404.
LOCAL_PROBE=''
LOCAL_STATUS=''
for attempt in $(seq 1 20); do
  LOCAL_PROBE=$(curl --noproxy '*' -sS --max-time 4 -H "Host: $DOMAIN" 'http://127.0.0.1/.well-known/acme-challenge/nova-probe' 2>/dev/null || true)
  if [[ "$LOCAL_PROBE" == 'nova-acme-probe' ]]; then
    echo "Desafio ACME local pronto (tentativa $attempt/20)."
    break
  fi
  if [[ "$attempt" -lt 20 ]]; then sleep 1; fi
done
if [[ "$LOCAL_PROBE" != 'nova-acme-probe' ]]; then
  LOCAL_STATUS=$(curl --noproxy '*' -sS -o /dev/null -w '%{http_code}' --max-time 5 -H "Host: $DOMAIN" 'http://127.0.0.1/.well-known/acme-challenge/nova-probe' || true)
  echo "Diagnóstico: Nginx novo não serviu o arquivo após 20 tentativas; HTTP local $LOCAL_STATUS." >&2
  echo 'Vhosts ativos para o domínio (sem exibir configuração privada):' >&2
  nginx -T 2>/dev/null | awk '/^# configuration file / {file=$0} /server_name[[:space:]]+nova\.gestaolojasonline\.tech/ {print file " | " $0}' >&2 || true
  fail 'Rota ACME local não respondeu. Reversão automática; não alterar outros vhosts.'
fi
PUBLIC_PROBE=$(curl --max-time 10 --silent --show-error --fail --resolve "$DOMAIN:80:$EXPECTED_IP" "http://$DOMAIN/.well-known/acme-challenge/nova-probe") || fail 'A porta 80 pública parece bloqueada; confira firewall da VPS/Hostinger.'
[[ "$PUBLIC_PROBE" == 'nova-acme-probe' ]] || fail 'O desafio ACME não é acessível no IP publicado.'

# Emite apenas certificado para o novo nome; não altera os demais vhosts.
docker run --rm --name nova-certbot-issue \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/lib/letsencrypt:/var/lib/letsencrypt \
  -v "$ACME_ROOT:$ACME_ROOT" \
  "$DOCKER_CERTBOT_IMAGE" certonly --webroot \
  -w "$ACME_ROOT" -d "$DOMAIN" \
  --non-interactive --agree-tos --register-unsafely-without-email \
  --cert-name "$CERT_NAME"
[[ -f "$CERT_ROOT/live/$CERT_NAME/fullchain.pem" ]] || fail 'Certificado não foi emitido.'
[[ -f "$CERT_ROOT/live/$CERT_NAME/privkey.pem" ]] || fail 'Chave TLS não foi emitida.'

# Segunda fase: apenas o NOVA na 443; HTTP redireciona para HTTPS.
TMP_CONF=$(mktemp /etc/nginx/conf.d/.nova-studio.XXXXXXXX)
cat > "$TMP_CONF" <<'EOF'
server {
    listen 80;
    server_name nova.gestaolojasonline.tech;
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/nova-studio-acme;
        default_type text/plain;
        try_files $uri =404;
    }
    location / { return 301 https://$host$request_uri; }
}
server {
    listen 443 ssl;
    server_name nova.gestaolojasonline.tech;
    ssl_certificate /etc/letsencrypt/live/nova.gestaolojasonline.tech/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/nova.gestaolojasonline.tech/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    client_max_body_size 65m;
    add_header Strict-Transport-Security "max-age=86400" always;
    location / {
        proxy_pass http://127.0.0.1:8018;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_connect_timeout 15s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF
chmod 644 "$TMP_CONF"
mv "$TMP_CONF" "$NGINX_CONF"
nginx -t || fail 'Configuração HTTPS não passou em nginx -t.'
systemctl reload nginx || fail 'Não foi possível ativar o novo HTTPS.'
HEALTH=$(curl -fsS --max-time 10 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/live") || fail 'HTTPS local não respondeu.'
[[ "$HEALTH" == *'"ok":true'* ]] || fail "Resposta /live inválida: $HEALTH"
API_STATUS=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/api/v1/projects")
[[ "$API_STATUS" == 401 ]] || fail "Segurança HTTPS falhou: HTTP $API_STATUS"

# Rotina exclusiva de renovação; não modifica certificados de outros projetos.
cat > /etc/cron.d/nova-studio-cert-renew <<'EOF'
24 4 * * * root /opt/nova-studio/deploy/hostinger/https-renew.sh >> /var/log/nova-studio-cert-renew.log 2>&1
EOF
chmod 644 /etc/cron.d/nova-studio-cert-renew
SUCCESS=1
printf '\nNOVA PUBLICADO: https://%s/\n' "$DOMAIN"
printf '%s\n' 'HTTPS válido localmente e API protegida. Para testar pelo iPhone, abra a URL pública.'
printf '%s\n' 'A chave privada da aplicação permanece em /opt/nova-studio/.env (NÃO a compartilhe no chat).'
