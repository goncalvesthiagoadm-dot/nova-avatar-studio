# NOVA Studio · v0.3 (ramificação de validação)

Plataforma independente de vídeo com avatares. **Não é o HeyGen e não integra ao Hermes**. Interface original, API para múltiplas integrações, módulos de renderização intercambiáveis.

## Narração feminina por IA — etapa em validação

A interface inclui **Gerar voz feminina IA**, que transforma o roteiro em um WAV com a voz brasileira `pf_dora` usando o serviço local Kokoro. A narração gerada substitui o áudio do projeto e pode ser usada na renderização MP4. O novo motor depende de um contêiner opcional com CPU/RAM suficientes; **não foi instalado nem ativado na VPS nesta entrega**. Sem Kokoro ativo, a função fica corretamente indisponível e o fluxo de vídeo anterior permanece intacto.

O guia de instalação isolada, pré-requisitos, privacidade, testes e limitações está em [docs/KOKORO-VOZ.md](docs/KOKORO-VOZ.md). Kokoro sintetiza voz, mas **não sincroniza os lábios**: essa etapa continua dependente de MuseTalk/GPU ou outro motor de vídeo validado.

## O que funciona hoje

1. Criar projetos e roteiro; ouvir prévia do texto com voz do navegador.
2. Enviar vídeo-base (MP4/MOV/WebM) e narração (WAV/MP3/M4A/AAC), ambos até 60 s.
3. Gerar MP4 com FFmpeg substituindo a faixa de áudio, com resultado real **mas sem sincronização labial**.
4. Conectar um **MuseTalk 1.5** instalado separadamente com modelos e GPU NVIDIA para sincronização de verdade. A integração é fornecida, mas **não foi testada nesta entrega em GPU**.
5. Acompanhar jobs por API e baixar MP4.

## Abrir no iPhone pelo Safari (publicação gratuita de teste)

Esta pasta está pronta para Render (`render.yaml` + `Dockerfile`), mas **não é um endereço publicado**. Para publicar em uma nova conta/repositório independente (não use o repositório do Hermes):

1. Conecte a sua conta **Render** no ChatGPT e uma origem Git exclusiva do NOVA, ou faça o deploy pelo painel Render com este projeto. Selecione o plano **Free**; não é necessário comprar domínio.
2. O Render atribui um endereço `https://...onrender.com` (somente após o deploy terminar). O processo usa `${PORT}` automaticamente e valida `/live`.
3. No Render, abra as variáveis do serviço e copie o `STUDIO_API_TOKEN` **gerado pelo próprio Render**. Não compartilhe esse segredo no chat ou em links.
4. No Safari, abra a URL real do serviço e toque **Entrar / Chave**; cole a chave e salve. O valor fica somente no armazenamento da sessão do navegador.
5. Se quiser um ícone no iPhone: Safari → Compartilhar → Adicionar à Tela de Início.

**Limitações relevantes do plano gratuito:** a instância adormece após 15 min de inatividade, demora para reativar e **perde projetos, SQLite, uploads e vídeos quando reinicia ou adormece**. Baixe o MP4 gerado antes disso. A plataforma gratuita não oferece GPU de vídeo e o MuseTalk permanecerá indisponível. Os recursos gratuitos são para avaliação, não para produção nem dados importantes. Contas com cobrança habilitada podem ter excedentes cobrados; verifique os limites no Render.

**Segurança:** configuração pública recusa iniciar sem chave forte; `/api/v1/` exige a chave, uploads não são públicos, a documentação da API também exige a chave e caminhos privados não são expostos. A página inicial pode ser visualizada sem autenticação, mas nenhuma operação de projeto fica acessível sem a chave. Não encaminhe seu link/chave para terceiros.

## Rodar localmente (Python 3.11+)

```bash
cd nova-avatar-studio
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
# FFmpeg também deve estar no PATH
uvicorn studio.app:app --host 127.0.0.1 --port 8018
```

Abra **http://127.0.0.1:8018**. Documentação API em `/api/docs`. No Windows, ative `.venv\\Scripts\\activate`.

### Docker (alternativa)

```bash
docker compose up --build -d
```

Abrir `http://127.0.0.1:8018`. O compose só escuta localhost para não expor sua mídia.

## Segurança

Para exigir chave em todas as chamadas `/api/v1/`, configure `STUDIO_API_TOKEN` com um segredo forte no ambiente. Na interface, clique "Chave da API" (armazenada na sessão do navegador). **Para operar remotamente ou multiusuário, instale autenticação, HTTPS, quotas e proteção do armazenamento antes de publicar.**

O arquivo de vídeo final sai do servidor. Não é armazenado em nenhuma conta paga. Não há dependências de serviços HeyGen.

## MuseTalk — instalação é separada

Conforme documentação oficial: https://github.com/TMElyralab/MuseTalk

- Clone e instale o projeto oficial em outro diretório, incluindo o ambiente Python com CUDA/Torch e seus pesos oficiais (MuseTalk v1.5, SD VAE, Whisper e demais modelos).
- Configure `MUSETALK_DIR` com o caminho absoluto para esse repositório e `MUSETALK_PYTHON` com o interpretador do ambiente Python correspondente.
- Mantenha `ffmpeg` e `nvidia-smi` disponíveis. Verifique `/api/v1/health` para ver o status real.
- O adaptador usa o contrato YAML `task_0: { video_path, audio_path, bbox_shift }` e `python -m scripts.inference --version v15` documentados pelo projeto oficial.
- O código do MuseTalk é MIT e seus autores permitem uso comercial dos pesos, mas dependências e mídias possuem licenças próprias. Leia-as antes de distribuir.
- GPU e configuração exigem recursos próprios; gratuito em licença **não significa processamento gratuito**.

## REA

Leia [`docs/REA-INVESTIGACAO.md`](docs/REA-INVESTIGACAO.md) para a metodologia de análise autorizada. O REA é ferramenta de pesquisa de aplicações, **não o modelo de geração audiovisual**.

## Testes

```bash
pip install pytest httpx
pytest -q
```

## API (exemplo)

```bash
curl -X POST http://127.0.0.1:8018/api/v1/projects \
  -H 'Content-Type: application/json' \
  -d '{"name":"Minha apresentação","script":"Olá!"}'
```

A documentação OpenAPI lista uploads, processamento e downloads.

## Arquitetura

```
studio/static/    Site web responsivo
studio/app.py     API FastAPI + SQLite + filas simples
studio/engines.py Motor FFmpeg + adaptador MuseTalk 1.5
storage/          Projetos, uploads, jobs, MP4s (criado ao executar)
docs/             Estudo do REA, requisitos e segurança
```

**Etapa seguinte:** instalar o motor e produzir um vídeo de qualidade comprovável; só então automatizar geração de voz, personagens e publicação em vários aplicativos.
