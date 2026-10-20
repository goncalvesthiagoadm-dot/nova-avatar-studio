# NOVA Studio — motor de voz Kokoro ONNX Lite (experimental)

Esta implementação é **opcional, isolada e desligada por padrão**. Nenhuma instalação de modelos, reinício de serviços ou modificação da VPS é realizada por um merge no GitHub. O serviço pesado original continua disponível no perfil `voice`, também opt-in; não habilitar os dois ao mesmo tempo.

## Diferença do Kokoro comum

- Motor **Kokoro ONNX 0.6.1**, modelo INT8 pt-BR `pf_dora`.
- Pesos principais: 114.119.327 bytes; vozes: 28.214.398 bytes; checksum SHA256 validado no build.
- Contêiner separado, **até 1 GiB RAM** e 1 CPU. Este limite não é previsão do consumo real: o modelo pode ultrapassá-lo e o contêiner falhar. **Não sobrecarrega o NOVA principal por padrão**.
- API interna compatível: `GET /health` e `POST /v1/audio/speech`. Não há portas publicadas.
- O modelo usa licença Apache 2.0; bibliotecas e vozes exigem conferência de licença conforme distribuição.

## Estado e validação

- A workflow `NOVA Voice Lite Smoke` monta a imagem num runner GitHub, limita sua memória a 1 GiB, inicia a API e **gera um áudio WAV real** em português. O arquivo é disponibilizado como artifact `nova-voice-ptbr-smoke` (sem dados privados, retenção de 7 dias).
- O CI padrão verifica contratos sem baixar modelos. A qualidade da voz **não é comprovada só pelo CI**: ouvir a amostra.
- Essa demonstração fora da VPS não valida a carga real da Hostinger.

## Critérios antes de iniciar na VPS Hostinger

De acordo com o diagnóstico em 20/10/2026, VPS de 7,8 GiB RAM, memória disponível 2,3 GiB, swap 2 GiB/2 GiB, sem GPU NVIDIA e com 44 GiB livres. Portanto **NÃO iniciar a instância Lite agora sem nova análise**. A swap cheia não prova, isoladamente, que o sistema está trocando páginas ativamente. Medir `vmstat 1 5`, consumo real por processo e tendência de MemAvailable em produção; idealmente separar folga de memória ou executar o processamento de áudio em outra máquina/nuvem.

Se houver folga comprovada, testar a imagem em janela controlada, sem iniciar outro serviço, com acompanhamento de OOM e latência. Fazer backup, definir `NOVA_KOKORO_URL=http://kokoro-lite:8880` somente no `.env` NOVA, iniciar somente `docker compose -p nova-studio --profile voice-lite up -d kokoro-lite`, e recriar somente `nova-studio` para obter a nova variável. **Não executar agora.**

Em caso de OOM, parar somente `kokoro-lite`, limpar apenas `NOVA_KOKORO_URL` e retornar o NOVA ao modo anterior. Não executar `docker system prune`, não alterar swap da VPS, não alterar Hermes, dashboards ou Nginx.

## Não resolve

- Animação fotorrealista e sincronização labial; para isso, serão necessários MuseTalk/GPU ou um motor adequado em outro ambiente.
- Uso simultâneo ou geração interativa em tempo real: o worker processa uma narração por vez.

Referências:
- https://github.com/thewh1teagle/kokoro-onnx/blob/main/examples/portuguese.py
- https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.1
