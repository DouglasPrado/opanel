# M05-08 — Railpack automatic build strategy

## Objective
Construir a imagem sem exigir Dockerfile: o Railpack detecta linguagem e framework, gera um Build Plan e o executa sobre BuildKit.

## Outcome
Um repositório de stack suportado vira imagem OCI sem que o usuário escreva um Dockerfile, com o plano detectado visível antes do primeiro build.

## References
- `docs/architecture/02-build-deploy.md` §6 (Railpack + BuildKit), §6.1 (estratégias), §6.2 (fluxo de build)
- `docs/architecture/10-ui-use-cases.md` UC-012, §10.1 (default saudável)
- `docs/annexes/D-test-strategy.md` §8 (pipeline de build), §8.1 (corpus de aplicações de teste)

## Preconditions
`M05-07` done.

## Scope
- Integração do Railpack como camada de **detecção e planejamento**; BuildKit como backend de construção.
- Detecção com preview do plano na UI antes do primeiro build (doc 10 §10.1: “default saudável”).
- Overrides controlados: build command, start command e `railpack.json` do projeto.
- Execução do plano sobre BuildKit dentro do builder isolado.
- Saída idêntica à da estratégia Dockerfile do ponto de vista do resto do sistema: uma imagem OCI publicada e identificada por digest.
- Corpus de fixtures cobrindo os stacks suportados.

## Out of Scope
- Dockerfile (`M05-09`).
- Build args e secrets (`M05-10`).
- Publicação e digest (`M05-12`).
- Multi-arch avançado (backlog).

## Application Layer
- **Providers:** adapter do Railpack, tratado como infraestrutura de build — **não** como comandos de shell espalhados pelo backend (doc 02 §6, regra explícita).

## Security Requirements
- O `railpack.json` do projeto é **entrada não confiável**: validado contra um schema, com overrides limitados a um conjunto conhecido. Ele não pode injetar comando arbitrário fora do sandbox do builder nem alterar limites de recurso.
- A detecção lê o repositório dentro do builder isolado; nada do repositório é executado fora dele.
- O plano gerado é registrado para auditoria e reprodutibilidade.
- Nenhum secret de runtime participa do build (doc 02 §6.3, regra: “segredo de runtime nunca deve ser necessário para construir a imagem”).

## Observability Requirements
- Plano detectado registrado com o build, para explicar por que a imagem ficou como ficou.
- Etapas do plano visíveis na timeline com duração.
- Métrica: taxa de detecção bem-sucedida por stack.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Detecção inconclusiva | Pedir overrides ou Dockerfile; **não** adivinhar (doc 10 UC-012). |
| `railpack.json` inválido | Rejeitado com erro claro apontando o campo. |
| `railpack.json` tentando escapar do sandbox | Rejeitado pela validação de schema e pelos limites do builder. |
| Build falha | Logs completos, `FAILED`, e a release atual do Service **não** muda. |
| Stack não suportado | Erro explicativo com o caminho alternativo (Dockerfile). |

## Acceptance Criteria
1. Um repositório de stack suportado gera Build Plan e produz imagem OCI **sem** Dockerfile.
2. O plano detectado é apresentado antes do primeiro build.
3. Overrides de build/start command e `railpack.json` são suportados.
4. `railpack.json` é validado contra schema; campos desconhecidos ou perigosos são rejeitados.
5. `railpack.json` não consegue escapar do sandbox nem alterar limites de recurso, provado por fixture.
6. Detecção inconclusiva pede overrides ou Dockerfile, sem adivinhar.
7. Build falho não altera a release atual do Service.
8. O Railpack é integrado como adapter, **não** como comandos de shell espalhados pelo backend, verificado por revisão e por teste estrutural.
9. Nenhum secret de runtime participa do build.
10. O plano gerado é registrado com o build.
11. O corpus cobre os stacks suportados e é versionado.

## Required Tests
- **Build Lab**: build Railpack por stack do corpus; detecção inconclusiva; build que falha.
- **unit**: validação do `railpack.json`; normalização de overrides.
- **security**: `railpack.json` malicioso; ausência de secret de runtime no build.
- **integration**: plano registrado com o build.

## Quality Gates
Local Quality Gate + Build Lab + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, corpus de stacks verde, `railpack.json` malicioso bloqueado, Critical/High = 0.
