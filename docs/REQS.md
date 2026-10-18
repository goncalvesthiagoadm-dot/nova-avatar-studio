# NOVA Studio — requisitos e decisões

**Objetivo:** Plataforma de vídeo com apresentadores própria, reusável por API em diversos produtos, sem subscrição de vídeo por uso. Não prometer equivalência visual ao HeyGen antes de testar.

## Fluxo implementado na versão 0.1
- Criar e listar projetos isolados.
- Escrever e salvar roteiro; ouvir prévia da voz do navegador (NÃO exporta narração).
- Validar upload de vídeo-base e áudio de até 60 segundos com FFprobe.
- Selecionar motor: (a) troca de áudio real, sem sync; (b) MuseTalk 1.5, somente se instalado em GPU.
- Enfileirar renderização, acompanhar status, exportar MP4.
- API JSON reutilizável e documentação OpenAPI.
- Autenticação opcional com X-API-Key; uso local como padrão.

## Fora de escopo nesta versão
- Geração de vídeo fotorrealista por IA sem GPU; treinamento/clonagem de apresentadores; narração TTS exportável.
- Real-time streaming, múltiplos usuários, faturamento, aprovação editorial, sincronização entre dispositivos.
- Publicação de site, instalação do REA, instalação de pesos MuseTalk ou hospedagem pública.

## Qualidade obrigatória antes de aprovar IA
- Identidade preservada, boca acompanha áudio, ausência de deformações, vídeo final reproduzível no Safari iOS.
- Comparação lado a lado com a **referência autorizada pelo usuário**, não com mídia privada de terceiros.
- Após aprovação visual: habilitar geração em lote, multilíngue, diversos formatos e integração plug-and-play.

## Segurança
- Apenas avatares/vozes com autorização de uso.
- Não copiar código, ativos ou modelos proprietários.
- Não publicar servidor na internet sem HTTPS e controle de acesso.
- Atenção: protótipo de usuário único, sem isolamento por tenant. Não hospedar vários clientes diretamente.
