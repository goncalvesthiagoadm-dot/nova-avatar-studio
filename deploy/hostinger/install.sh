#!/usr/bin/env bash
# NOVA Studio independente em /opt/nova-studio. Não modifica nginx, TLS ou outros serviços.
set -Eeuo pipefail
umask 077
BASE=/opt/nova-studio
REPO=https://github.com/goncalvesthiagoadm-dot/nova-avatar-studio.git
PROJECT=nova-studio
EXPECTED_COMMIT="${NOVA_EXPECTED_COMMIT:-}"
fail() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }
[[ $(id -u) -eq 0 ]] || fail 'Execute com sudo.'
if [[ -n "$EXPECTED_COMMIT" && ! "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  fail 'NOVA_EXPECTED_COMMIT inválido.'
fi
for c in git docker curl openssl ss awk df; do
  command -v "$c" >/dev/null 2>&1 || fail "Falta $c. Instalação interrompida; nenhuma dependência global será alterada."
done
docker compose version >/dev/null 2>&1 || fail 'Docker Compose v2 é necessário.'
docker info >/dev/null 2>&1 || fail 'Docker não está ativo.'
[[ ! -L "$BASE" ]] || fail 'O diretório NOVA não pode ser um link simbólico.'
if [[ -e "$BASE" ]]; then
  [[ -d "$BASE/.git" ]] || fail 'Destino já existe e não é checkout Git. Não alterado.'
  [[ "$(git -C "$BASE" remote get-url origin 2>/dev/null || true)" == "$REPO" ]] || fail 'Repositório inesperado no destino. Não alterado.'
  [[ "$(git -C "$BASE" branch --show-current)" == "main" ]] || fail 'O checkout NOVA não está em main. Não alterado.'
  [[ -z "$(git -C "$BASE" status --porcelain --untracked-files=no)" ]] || fail 'Há mudanças locais. Pare para revisão.'
fi
if ss -H -lnt '( sport = :8018 )' | grep -q .; then
  if [[ ! -e "$BASE/compose.yml" ]] || ! docker compose -p "$PROJECT" -f "$BASE/compose.yml" ps --status running -q 2>/dev/null | grep -q .; then
    fail 'Porta 8018 ocupada. Não sobrescrever outro serviço.'
  fi
fi
mem_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
[[ -n "$mem_kb" && "$mem_kb" -ge 1150000 ]] || fail 'Memória disponível inferior a 1,1 GB; não afetar outros serviços.'
disk_kb="$(df -Pk /opt | awk 'NR==2 {print $4}')"
[[ -n "$disk_kb" && "$disk_kb" -ge 3500000 ]] || fail 'Disco com menos de 3,5 GB livres; não afetar outros serviços.'
if [[ -e "$BASE" ]]; then
  git -C "$BASE" fetch origin main
  if [[ -n "$EXPECTED_COMMIT" ]]; then
    fetched_commit="$(git -C "$BASE" rev-parse FETCH_HEAD)"
    [[ "$fetched_commit" == "$EXPECTED_COMMIT" ]] || fail 'O main mudou desde o início do deploy. Nenhuma atualização aplicada.'
  fi
  git -C "$BASE" merge --ff-only FETCH_HEAD || fail 'Atualização cancelada (não é fast-forward).'
else
  git clone --depth=1 --branch main "$REPO" "$BASE"
  if [[ -n "$EXPECTED_COMMIT" ]]; then
    [[ "$(git -C "$BASE" rev-parse HEAD)" == "$EXPECTED_COMMIT" ]] || fail 'O main mudou durante o deploy. Nenhuma imagem foi criada.'
  fi
fi
cd "$BASE"
if [[ ! -f .env ]]; then
  secret="$(openssl rand -hex 32)"
  printf 'STUDIO_API_TOKEN=%s\n' "$secret" > .env
  unset secret
fi
chmod 600 .env
grep -Eq '^STUDIO_API_TOKEN=[A-Za-z0-9_-]{24,}$' .env || fail 'Chave da API ausente ou fraca.'
docker compose -p "$PROJECT" -f compose.yml config -q
docker compose -p "$PROJECT" -f compose.yml up -d --build --no-deps
for i in $(seq 1 24); do
  if curl -fsS --max-time 4 http://127.0.0.1:8018/live | grep -q '"ok":true'; then break; fi
  sleep 5
done
curl -fsS --max-time 5 http://127.0.0.1:8018/live | grep -q '"ok":true' || fail 'NOVA não respondeu na porta local.'
status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8018/api/v1/projects)"
[[ "$status" == 401 ]] || fail "Segurança falhou (esperado 401, recebido $status)."
printf '\nNOVA instalado localmente; API protegida.\n'
printf '%s\n' 'HTTPS e domínio ainda precisam ser configurados separadamente.'
printf '%s\n' 'A chave está em /opt/nova-studio/.env. NÃO copie a chave para o chat.'
printf '%s\n' 'Estado: cd /opt/nova-studio && docker compose -p nova-studio ps'
