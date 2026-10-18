#!/usr/bin/env bash
# Diagnóstico do NOVA: SOMENTE LEITURA. Não modifica sistema ou serviços.
set -Eeuo pipefail
printf '\n=== NOVA Studio / Hostinger: diagnóstico seguro ===\n'
printf 'Data UTC: %s\n' "$(date -u +%FT%TZ)"
printf 'Host: %s\n' "$(hostname)"
printf 'Usuário: %s (UID %s)\n' "$(id -un)" "$(id -u)"
printf 'SO: '; . /etc/os-release; printf '%s\n' "$PRETTY_NAME"
printf '\nMemória:\n'; free -h || true
printf '\nDisco:\n'; df -h /opt /var/lib/docker 2>/dev/null || df -h /opt || true
printf '\nFerramentas:\n'
for app in git docker nginx curl openssl ss; do
  if command -v "$app" >/dev/null 2>&1; then printf 'OK %s\n' "$app"; else printf 'AUSENTE %s\n' "$app"; fi
done
if command -v docker >/dev/null 2>&1; then
  docker compose version 2>&1 || true
  if docker info >/dev/null 2>&1; then echo 'Docker: ativo'; else echo 'Docker: inacessível (tente sudo)'; fi
fi
printf '\nPorta local 8018 (vazio = livre):\n'
if command -v ss >/dev/null 2>&1; then ss -H -lnt '( sport = :8018 )' || true; fi
printf '\n/opt/nova-studio:\n'
if [[ -e /opt/nova-studio ]]; then echo 'Diretório já existe; verificar antes de atualizar'; else echo 'Livre'; fi
printf '\nDiagnóstico concluído. Nenhuma alteração realizada.\n'
