# Publicar o NOVA pela GitHub Actions

O workflow `.github/workflows/deploy-hostinger.yml` publica somente o projeto NOVA em `/opt/nova-studio`. Ele executa automaticamente somente após a CI **NOVA Studio CI** concluir com sucesso para um `push` em `main`, ou manualmente a partir de `main`. Exige uma chave de host SSH fixada previamente e chama o instalador NOVA existente. O instalador confere recursos, mantém o volume de dados e valida `/live` e HTTP 401 depois do build.

## Configuração necessária uma vez

No repositório GitHub, crie o Environment `nova-production` e configure:

**Environment variables**

- `NOVA_SSH_HOST`: endereço da VPS.
- `NOVA_SSH_USER`: usuário SSH com execução não interativa de `sudo` para o instalador do NOVA.
- `NOVA_SSH_PORT`: porta SSH, se diferente de `22`. Se omitida, usa `22`.

**Environment secrets**

- `NOVA_SSH_PRIVATE_KEY`: chave privada de implantação dedicada ao NOVA. Não reutilize a chave da API nem uma chave pessoal.
- `NOVA_SSH_KNOWN_HOSTS`: linha `known_hosts` para o host, obtida e verificada por um canal confiável. O workflow recusa chaves de host desconhecidas e não usa `ssh-keyscan` no momento do deploy.

A chave pública correspondente precisa estar autorizada no usuário SSH da VPS. O usuário precisa de `sudo` sem solicitação interativa para executar o instalador. Não cole nenhuma dessas chaves em issues, PRs ou no chat.

## Execução automática ou manual

Após configurar as credenciais do Environment, um `push` ou merge em `main` inicia `NOVA Studio CI`. **Somente após sucesso**, o workflow de deploy executa. Falhas de CI e execuções de PRs não publicam nada.

Alternativamente, abra **Actions → Deploy NOVA to Hostinger → Run workflow**, selecione `main` e execute. O workflow envia à VPS o SHA exato a publicar e apresenta diagnóstico de memória, disco e presença de GPU (não mostra segredos).

Se houver divergência com `main`, mudanças locais, recursos insuficientes, falta de SSH/sudo ou falha de health check, o instalador interrompe o deploy; não modifica Hermes, dashboards, Nginx nem outros serviços.

**Nota:** o botão de voz por IA aparece na interface após o deploy, mas continua indisponível até o Kokoro ser ativado isoladamente depois de medirmos os recursos. A publicação de código **não inicia** o contêiner Kokoro e **não entrega lip-sync**.
