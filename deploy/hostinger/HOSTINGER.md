# Instalação NOVA Studio na VPS Hostinger

**Somente NOVA.** Não modificar Hermes Particular, Hermes Gestão ou qualquer dashboard. O repositório é independente. Os scripts não mexem em nginx, Cloudflare, DNS, firewall ou serviços pré-existentes.

## Acesso pelo iPhone
Hostinger hPanel > VPS > Gerenciar > Visão Geral > Web Console (Terminal do navegador). Não informe senhas no chat.

## Etapa 1: diagnóstico SEM alterações
```bash
curl -fsSL https://raw.githubusercontent.com/goncalvesthiagoadm-dot/nova-avatar-studio/main/deploy/hostinger/preflight.sh -o /tmp/nova-preflight.sh && bash /tmp/nova-preflight.sh
```
Envie apenas o diagnóstico (não tokens nem senhas). É obrigatório verificar se Docker Compose está ativo e há memória e espaço livres suficientes.

## Etapa 2: instalar localmente (após diagnóstico)
```bash
curl -fsSL https://raw.githubusercontent.com/goncalvesthiagoadm-dot/nova-avatar-studio/main/deploy/hostinger/install.sh -o /tmp/nova-install.sh && sudo bash /tmp/nova-install.sh
```

O instalador cria somente `/opt/nova-studio`, projeto Compose `nova-studio`, um volume persistente e chave forte local em `.env`. Usa exclusivamente `127.0.0.1:8018`. Limites: 1 núcleo CPU, 1536 MB RAM. Falha em caso de porta ocupada, recursos insuficientes, falta de Docker ou alterações locais existentes. Não modifica aplicações da Gestão/Hermes.

## Etapa 3: publicação externa separada
Proposta: `nova.gestaolojasonline.tech` (o DNS **ainda não foi validado**). Confirmar DNS Cloudflare, certificados HTTPS e configuração Nginx vigente. Criar apenas vhost próprio, sem editar os demais; executar `nginx -t` antes do reload. Testar publicamente `/live` e garantir 401 em `/api/v1/projects` sem token. Nunca tornar `/opt/nova-studio/.env` público.

## Operação
- Verificar somente NOVA: `cd /opt/nova-studio && sudo docker compose -p nova-studio ps`
- Logs somente NOVA: `cd /opt/nova-studio && sudo docker compose -p nova-studio logs --tail=80 nova-studio`
- Parar somente NOVA: `cd /opt/nova-studio && sudo docker compose -p nova-studio stop`
- Iniciar somente NOVA: `cd /opt/nova-studio && sudo docker compose -p nova-studio start`

Não executar `docker compose down -v` (apaga dados NOVA) nem `docker system prune` em VPS compartilhada.

**Limitação:** v0.2 permite substituir áudio em vídeo, não sincroniza lábios ou cria animação fotorrealista automaticamente. A VPS sem GPU não substitui processamento HeyGen.
