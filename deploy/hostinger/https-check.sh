#!/usr/bin/env bash
# NOVA Studio / Hostinger: diagnóstico externo APENAS LEITURA.
# Não lê nem imprime tokens, chaves, senhas ou conteúdo de configurações.
set -u
DOMAIN="nova.gestaolojasonline.tech"
printf '\n=== NOVA STUDIO / PRONTIDAO HTTPS ===\n'
printf 'Data (UTC): %s\n' "$(date -u +%FT%TZ)"
printf 'Dominio planejado: %s\n' "$DOMAIN"
printf '\n[1] Aplicacao e container NOVA\n'
if command -v docker >/dev/null 2>&1; then
  docker ps --filter 'label=com.docker.compose.project=nova-studio' --format '{{.Names}} | {{.Status}} | {{.Ports}}' 2>&1 || true
fi
printf '\n[2] Testes locais (sem revelar chave)\n'
if command -v curl >/dev/null 2>&1; then
  printf '/live: '
  curl -fsS --max-time 5 'http://127.0.0.1:8018/live' || true
  printf '\n/api/v1/projects sem chave (esperado HTTP 401): '
  curl -sS -o /dev/null -w '%{http_code}\n' --max-time 5 'http://127.0.0.1:8018/api/v1/projects' || true
fi
printf '\n[3] Recursos atuais\n'
free -h 2>/dev/null || true
df -h /opt 2>/dev/null || true
printf '\n[4] DNS publico consultado pelo servidor\n'
if command -v getent >/dev/null 2>&1; then
  result="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u | head -n 8)"
  if [[ -n "$result" ]]; then printf '%s\n' "$result"; else echo 'SEM REGISTRO A IPv4 RESOLVIDO'; fi
fi
printf '\n[5] IPv4 publico de saida (confirme no painel Hostinger antes de usar no DNS)\n'
curl -4fsS --max-time 6 'https://api.ipify.org' || true
printf '\n'
printf '\n[6] Servico Nginx e nomes configurados (sem exibir arquivo completo)\n'
if command -v systemctl >/dev/null 2>&1; then
  printf 'nginx: '; systemctl is-active nginx 2>/dev/null || true
fi
if command -v nginx >/dev/null 2>&1; then
  nginx -t 2>&1 | tail -n 4
  nginx -T 2>/dev/null | awk '$1 == "server_name" { print $0 }' | sort -u | head -n 30
fi
printf '\n[7] Ferramentas HTTPS disponiveis\n'
for exe in certbot acme.sh openssl; do
  if command -v "$exe" >/dev/null 2>&1; then echo "OK: $exe"; else echo "Nao instalado: $exe"; fi
done
printf '\n=== FIM: NENHUMA ALTERACAO REALIZADA ===\n'
