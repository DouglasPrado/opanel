# Conversion Report

## Resultado

- Documentos DOCX convertidos: **19**
- Arquitetura: **10 arquivos Markdown**
- Anexos: **9 arquivos Markdown**
- Links locais quebrados: **0**
- Referências a mídia ausente: **0**
- Artefatos Pandoc `:::`: **0**
- Artefatos de atributos Pandoc: **0**
- Linhas de paginação detectadas: **0**

## Estrutura

```text
docs/
├── MASTER.md
├── MANIFEST.json
├── CONVERSION_REPORT.md
├── architecture/
├── annexes/
├── decisions/
└── implementation/
```

## Conversão

A conversão foi feita programaticamente de DOCX para GitHub-Flavored Markdown. Headings, listas, tabelas, links e blocos de código foram preservados sempre que representáveis. Tabelas/callouts mais complexos podem permanecer como HTML embutido, que é válido em GitHub Markdown.

## Validação

- Todos os arquivos foram lidos novamente como UTF-8.
- Todos os links locais do `MASTER.md` e demais Markdown foram validados.
- Não há referências a imagens/mídia externa extraídas do DOCX.
- Não foram detectados resíduos comuns de paginação ou containers Pandoc.

## Pendência de decisão detectada

O **Anexo G** convertido preserva a decisão existente no DOCX-fonte que descreve `Next.js + Rails API` como baseline inicial. Em conversa posterior, a direção técnica evoluiu para **Rails + Inertia + React/TypeScript**, aproveitando os componentes React existentes.

A conversão não altera silenciosamente decisões da especificação aprovada. Antes do Implementation Pack M00, recomenda-se registrar/finalizar essa mudança e atualizar o Anexo G (e qualquer outro documento impactado) de forma deliberada.

## Integridade

Checksums SHA-256 dos 19 documentos normativos convertidos estão registrados em `MANIFEST.json`.
