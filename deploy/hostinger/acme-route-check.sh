#!/usr/bin/env bash
# NOVA Studio: diagnóstico APENAS LEITURA para falha ACME local.
# Não altera nginx, firewall, DNS, contêineres ou serviços existentes.
set -u
DOMAIN=nova.gestaolojasonline.tech
PROBE=/var/www/nova-studio-acme/.well-known/acme-challenge/nova-probe
echo "=== NOVA: diagnóstico de rota ACME (somente leitura) ==="
echo "UTC: $(date -u +%FT%TZ)"
echo
echo "[1] Estado do Nginx"
if command -v nginx >/dev/null 2>&1; then
  nginx -t 2>&1 | tail -n 4
else
  echo "nginx não encontrado"
fi
echo
echo "[2] Portas HTTP e HTTPS em escuta"
if command -v ss >/dev/null 2>&1; then
  ss -H -ltnp '( sport = :80 or sport = :443 )' 2>&1 | head -n 30
else
  echo "ss não encontrado"
fi
echo
echo "[3] Configuração NOVA após a reversão"
if test -e /etc/nginx/conf.d/nova-studio.conf; then
  echo "ATENÇÃO: /etc/nginx/conf.d/nova-studio.conf ainda existe"
else
  echo "Vhost NOVA removido após falha (esperado)"
fi
if test -f "$PROBE"; then
  echo "Arquivo desafio: existe"
  if test -r "$PROBE"; then echo "Arquivo desafio: legível pelo usuário atual"; fi
  ls -ld /var/www/nova-studio-acme /var/www/nova-studio-acme/.well-known /var/www/nova-studio-acme/.well-known/acme-challenge 2>/dev/null
  ls -l "$PROBE" 2>/dev/null
else
  echo "Arquivo desafio: não encontrado"
fi
echo
echo "[4] Vhosts Nginx: somente arquivo, listen e server_name (sem segredos)"
if command -v nginx >/dev/null 2>&1; then
  nginx -T 2>/dev/null | awk '
    /^# configuration file / { source=$0; next }
    /^[[:space:]]*listen[[:space:]]/ { print source " | " $0 }
    /^[[:space:]]*server_name[[:space:]]/ { print source " | " $0 }
  ' | head -n 90
fi
echo
echo "[5] Resposta HTTP local sem configuração NOVA"
if command -v curl >/dev/null 2>&1; then
  for HOST in "127.0.0.1" "localhost"; do
    echo -n "$HOST com Host: $DOMAIN -> "
    curl -sS -o /dev/null -w 'HTTP %{http_code}; IP=%{remote_ip}; porta=%{remote_port}; redireciona=%{redirect_url}\n' --max-time 6 -H "Host: $DOMAIN" "http://$HOST/.well-known/acme-challenge/nova-probe" || true
  done
  echo -n "NOVA local /live: "
  curl -fsS --max-time 5 http://127.0.0.1:8018/live || true
  echo
fi
echo "=== FIM: nenhuma alteração efetuada ==="
