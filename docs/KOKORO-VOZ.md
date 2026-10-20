# NOVA Studio — narração IA feminina em português

Esta etapa conecta a voz `pf_dora` do Kokoro a um projeto NOVA, exclusivamente por serviço local e isolado. Não acessa HeyGen, Hermes, dashboards ou APIs pagas.

## Incluído no código

- Botão **Gerar voz feminina IA** no editor: salva o roteiro e chama `POST /api/v1/projects/{id}/narration`.
- Um roteiro de 1 a 700 caracteres gera WAV real (máximo 60 segundos); o arquivo substitui **somente o áudio do projeto**, não o vídeo.
- O mesmo áudio gerado alimenta o renderizador existente e pode ser ouvido no player do editor.
- Autenticação já existente via `STUDIO_API_TOKEN`; bloqueio de URL externa para impedir envio de roteiros a serviços remotos.
- O botão permanece **desativado** quando Kokoro não estiver instalado/saudável. Não há geração simulada.

## Requisitos e limites

- Imagem opcional: `ghcr.io/remsky/kokoro-fastapi-cpu:latest`, com API de voz compatível `/v1/audio/speech`.
- Reservar **até 2 GB adicionais de RAM** para o serviço experimental CPU e espaço livre para download de modelos; a exigência real deve ser medida no servidor.
- CPU pode gerar áudio com demora. Avaliar latência e qualidade em pt-BR antes de aprovar.
- O Kokoro TTS **não movimenta a boca**; MuseTalk requer GPU NVIDIA, um motor diferente.
- **Não iniciar o perfil voice sem diagnóstico de memória da VPS**. A instalação padrão continua sem Kokoro.

## Habilitação após diagnóstico positivo

O Compose inclui o perfil opcional `voice`. Todos os comandos abaixo são do projeto **NOVA**, em `/opt/nova-studio`. Não usar em outros projetos.

1. Fazer backup do projeto e executar `deploy/hostinger/preflight.sh`. Exigir folga de RAM e disco antes de prosseguir.
2. Na configuração local `.env` do NOVA, definir `NOVA_KOKORO_URL=http://kokoro-tts:8880` (apenas hostname da rede Docker do NOVA).
3. Iniciar o serviço opcional: `docker compose -p nova-studio --profile voice up -d kokoro-tts`. **Não abrir a porta 8880 no host**.
4. Verificar `docker compose -p nova-studio --profile voice logs --tail=80 kokoro-tts` e aguardar download dos pesos.
5. Recriar apenas o serviço NOVA para obter a nova variável: `docker compose -p nova-studio up -d --no-deps nova-studio`.
6. Abrir a API protegida `GET /api/v1/health` e confirmar `voices[0].available=true`.
7. No editor NOVA, salvar texto curto, gerar narração, ouvir WAV e baixar o MP4 com áudio.

Não iniciar automaticamente o segundo contêiner nem habilitar a produção sem confirmação dos recursos. Se houver falhas, desabilitar apenas `NOVA_KOKORO_URL` e recriar `nova-studio`; o renderizador FFmpeg anterior continua funcionando.

## Testes incluídos

Os testes simulam apenas a resposta HTTP do motor para garantir o contrato e segurança, além de usarem FFmpeg para validar um WAV real. **Eles não comprovam a qualidade auditiva do Kokoro nem teste de produção**. A liberação funcional requer uma execução na VPS, arquivo de áudio gravado e avaliação da voz.

## Referências

- https://github.com/remsky/Kokoro-FastAPI
- https://github.com/thewh1teagle/kokoro-onnx
- https://huggingface.co/hexgrad/Kokoro-82M
