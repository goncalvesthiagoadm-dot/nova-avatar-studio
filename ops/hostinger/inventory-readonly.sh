#!/usr/bin/env bash
# HOSTINGER / REV: INVENTARIO EXCLUSIVAMENTE LEITURA
# Nunca ler .env, tokens, conteudo de logs, arquivos financeiros ou credenciais.
# Nunca parar, reiniciar, instalar, apagar ou alterar servicos.
set -u
export LC_ALL=C
section() { printf '\n========== %s ==========\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
section "INICIO / INFORMACOES GERAIS"
date -Is
printf 'Hostname: '; hostname
printf 'Sistema: '; ( . /etc/os-release && echo "$PRETTY_NAME" ) 2>/dev/null || uname -s
uname -r
uptime
printf 'Nucleos CPU: '; nproc 2>/dev/null || true

section "MEMORIA, SWAP, CPU / AMOSTRA"
free -h
awk '/^MemAvailable:|^SwapTotal:|^SwapFree:/ {print}' /proc/meminfo
if have vmstat; then vmstat 1 4; fi
if [[ -r /proc/pressure/memory ]]; then
  printf 'Memory pressure PSI: '; head -n 2 /proc/pressure/memory | tr '\n' ' '; echo
fi

section "PROCESSOS COM MAIOR USO HISTORICO DE CPU (nao instantaneo)"
ps -eo pid,ppid,user,etimes,pcpu,pmem,rss,comm --sort=-pcpu 2>/dev/null | head -n 26

section "ARMAZENAMENTO / PONTOS DE MONTAGEM"
df -h / /opt /var/lib/docker 2>/dev/null | awk '!seen[$1,$6]++'
if have docker && docker info >/dev/null 2>&1; then
  section "DOCKER / CONTAINERS INSTALADOS, RODANDO OU PARADOS"
  docker ps -a --format 'Nome={{.Names}} | Imagem={{.Image}} | Estado={{.Status}} | Portas={{.Ports}}' 2>/dev/null | head -n 60
  section "DOCKER / CONSUMO ATUAL (SOMENTE ATIVOS)"
  timeout 15 docker stats --no-stream --format '{{.Name}} | CPU={{.CPUPerc}} | RAM={{.MemUsage}}' 2>/dev/null | head -n 45 || true
  section "DOCKER / DISCO"
  timeout 15 docker system df 2>/dev/null || true
  section "DOCKER / VOLUMES (SO NOMES; NAO CONTEUDO)"
  docker volume ls --format '{{.Name}}' 2>/dev/null | head -n 45
fi

section "SERVICOS SYSTEMD RELEVANTES (ESTADO, NAO CONFIGURACAO)"
if have systemctl; then
  for svc in nginx cloudflared weberp-cloud touchpay-cnpem touchpay-pg \
      gestaolojas-api gestaolojas-normalizador-v8 gestaolojas-incidentes \
      gestaolojas-github-frontend gestaolojas-github-radar-backend \
      gestaolojas-backup gestaolojas-contexto-externo \
      client-flow-history desktop-commander-remote desktop-commander-refresh \
      oracle-socks compat \
      hermes hermes-worker hermes-scheduler hermes-telegram \
      hermes-email hermes-email-automation hermes-alert-delivery \
      hermes-channel-delivery hermes-admin-action-worker \
      hermes-cloudflared hermes-public-tunnel hermes-mcp \
      hermes-git-deployer hermes-maintenance hermes-restore-drill \
      omniroute casa-smart-homeassistant; do
    unit="$svc.service"
    state=$(systemctl show "$unit" --property=LoadState --value --no-pager 2>/dev/null || true)
    if [[ -n "$state" && "$state" != not-found ]]; then
      printf '%-38s' "$unit"
      systemctl show "$unit" --property=ActiveState,UnitFileState,NRestarts,MemoryCurrent \
        --no-pager 2>/dev/null | tr '\n' ' '
      printf '\n'
    fi
  done
  section "OUTROS SYSTEMD PERSONALIZADOS INSTALADOS (NOMES E HABILITACAO)"
  systemctl list-unit-files --no-pager --no-legend 2>/dev/null | \
    awk '$1 ~ /^(hermes|gestaolojas|touchpay|weberp|nova|cloudflared|desktop-commander|omniroute|oracle|compat|casa|client-flow)/ {print $1,$2}' | \
    head -n 95
  section "TIMERS (INCLUSIVE OS QUE ESTAO PARADOS)"
  systemctl list-timers --all --no-legend --no-pager 2>/dev/null | \
    grep -Ei 'hermes|gestao|touchpay|weberp|compat|nova|oracle|client-flow|commander|omni|backup' | head -n 55 || true
  section "UNIDADES COM ERRO (SOMENTE NOMES/ESTADO)"
  systemctl --failed --no-legend --no-pager 2>/dev/null | head -n 30
fi

section "AGENDAMENTOS CRON (SOMENTE NOMES E QUANTIDADE)"
if [[ -d /etc/cron.d ]]; then
  find /etc/cron.d -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort | head -n 60
fi
if have crontab; then
  printf 'Quantidade de tarefas ativas no crontab root: '
  (crontab -l -u root 2>/dev/null || true) | awk '!/^ *($|#)/ {n++} END{print n+0}'
fi

section "PORTAS TCP EM ESCUTA (SEM DIVULGAR IP DO SERVIDOR)"
if have ss; then
  ss -H -ltn 2>/dev/null | awk '{
    addr=$4; port=addr; sub(/^.*:/,"",port);
    if (addr ~ /^127[.]/ || index(addr,"[::1]:")==1) scope="local";
    else if (addr ~ /^0[.]0[.]0[.]0:/ || index(addr,"[::]:")==1 || index(addr,"*:")==1) scope="todas_interfaces";
    else scope="outra_interface";
    if (port ~ /^[0-9]+$/) print scope,port
  }' | sort -k2,2n -k1,1 | uniq | head -n 60
fi

section "DOMINIOS NGINX PUBLICADOS (SO SERVER_NAME)"
if have nginx; then
  timeout 8 nginx -T 2>/dev/null | awk '$1=="server_name" {
     for (i=2;i<=NF;i++) {gsub(/;/,"",$i); if (length($i)<125) print $i}
  }' | sort -u | head -n 60
fi

section "PROJETOS CONHECIDOS E USO DE DISCO (SCAN LIMITADO)"
for path in /opt/gestaolojas /opt/gestaolojas-github-prod-20260914 \
            /opt/hermes /opt/nova-studio; do
  if [[ -d "$path" ]]; then
    if have nice && have timeout; then
      timeout 12 nice -n 15 du -shx "$path" 2>/dev/null || echo "Estimativa nao concluida: $path"
    else
      printf 'Existe: %s (tamanho nao medido)\n' "$path"
    fi
  fi
done
section "TESTES DE VIDA HTTP SOMENTE EM LOOPBACK (CODIGO HTTP)"
if have curl; then
  for entry in 'NOVA|http://127.0.0.1:8018/live' \
               'HERMES|http://127.0.0.1:21402/health' \
               'HERMES_GESTAO|http://127.0.0.1:22400/health'; do
    name="${entry%%|*}"; url="${entry#*|}"
    status=$(curl --noproxy '*' --max-time 3 -sS -o /dev/null \
      -w '%{http_code}' "$url" 2>/dev/null || echo 'indisponivel')
    printf '%-18s HTTP %s\n' "$name" "$status"
  done
fi
section "FIM / INVENTARIO SOMENTE LEITURA"
echo 'O relatorio contem apenas metadados operacionais: nao inclui logs, senhas, .env ou conteudo de vendas.'
echo 'NAO executar docker prune, systemctl stop/disable, apt upgrade ou remover diretorios com base apenas nesta fotografia.'
