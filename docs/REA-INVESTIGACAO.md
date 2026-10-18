# REA — investigação para um editor próprio (clean room)

Este projeto NÃO é uma cópia do código do HeyGen. A ideia é estudar **fluxos observáveis publicamente** e desenvolver implementação própria.

## Ferramenta oficial
- https://github.com/morluto/rea
- https://rea.tools
- Com Node.js compatível (22.19+, 24.11+ ou 26+), instalar:
  `npx rea-agents setup`
- O REA não está embutido neste projeto: é uma ferramenta de investigação local separada e opcional.

## Perguntas de pesquisa
1. Como o editor organiza painel de cenas, avatar, texto e áudio?
2. Como comunica a diferença entre prévia e vídeo final?
3. Como o usuário configura proporção 16:9, 9:16 e 1:1?
4. Que feedback a interface apresenta durante processamento e falhas?
5. Quais funções ajudam a reutilizar uma mesma apresentadora em vários projetos?

## Método autorizado
- Observe somente páginas públicas e sua própria sessão de teste, obedecendo os termos de uso.
- Registre telas, cliques, ações do usuário e descrições; jamais replique arquivos proprietários, scripts ofuscados, chaves, cookies, modelos privados ou dados de terceiros.
- Reconstrua requisitos e comportamento desejado a partir de evidências, mantendo identidade visual e código originais.
- Documente hipótese, observação, decisão, limitação e implementação em uma tabela de evidências.

## Artefatos de saída
- `docs/REQS.md` com jornadas, critérios de aceitação e prioridades.
- Uma prova real de **qualidade audiovisual** (não apenas interface) antes de integrar IA ao núcleo.
- Adaptadores independentes com contratos claros (`studio/engines.py`).

## Condições
Não acessar, modificar, copiar, exportar, usar dados ou depender do Hermes Particular, Hermes Gestão, dashboards, credenciais, banco de dados ou tokens desses sistemas.
