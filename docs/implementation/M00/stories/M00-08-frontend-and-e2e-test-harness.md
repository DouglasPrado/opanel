# M00-08 — Frontend component tests and browser E2E harness

## Objective
Estabelecer o harness de teste de componente (Vitest + Testing Library) e de E2E de browser (Playwright), com a política de seletores semânticos exigida pelo Anexo D §11.1.

## Outcome
`bin/test:js` roda testes de componente; `bin/test:e2e` roda uma jornada de browser contra a aplicação real; ambos produzem artefatos de diagnóstico em falha.

## References
- `docs/annexes/D-test-strategy.md` §11 (E2E e jornadas), §11.1 (regra de seletores), §21 (harnesses)
- `docs/architecture/10-ui-use-cases.md` §25 (estados universais de UI), §28 (acessibilidade)
- `docs/annexes/B-nfr-slos.md` §18 (NFRs de UX e acessibilidade)
- `docs/implementation/SPEC_CONFLICTS.md` SC-03

## Preconditions
`M00-04` done. `M00-05` recomendado para ter componentes reais a testar.

## Scope
- Vitest + Testing Library configurados para `app/frontend/`.
- Playwright configurado contra a aplicação real, com trace, screenshot e vídeo em falha.
- **Política de seletores**: roles, atributos semânticos e test IDs estáveis; classes CSS são proibidas como seletor e a proibição é verificada por lint.
- Helpers para os estados universais do doc 10 §25: loading, empty, no permission, offline, stale, operation running, partial failure.
- Checagem automatizada de acessibilidade nos fluxos cobertos, com meta WCAG 2.2 AA.
- Uma jornada E2E de smoke: abrir a aplicação, renderizar a página de exemplo, verificar o estado de erro.

## Out of Scope
- Jornadas E2E de domínio (cada Milestone traz as suas; M01 traz o vertical slice).
- Testes de carga (M13).
- Testes visuais de regressão de pixel.

## UI Impact
Define como toda UI será testada. A partir daqui, uma Story de UI sem cobertura de estado de erro/empty/forbidden é finding de review, não “polish futuro”.

## Security Requirements
- Artefatos de falha (screenshot, trace, vídeo) passam por redaction: nenhum valor de secret, token ou header de autorização pode ser arquivado.
- Credenciais usadas em E2E são de teste e rotacionáveis.

## Observability Requirements
Falha de E2E produz trace navegável, screenshot e o `request_id` da requisição que falhou, para correlacionar com o log do servidor.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Seletor frágil por classe CSS | Lint reprova antes do commit. |
| E2E intermitente | Quarentena com dono e prazo (Anexo D §20.1); retry do harness é distinguível de retry de assertion. |
| Aplicação não sobe para o E2E | Falha explícita de setup, não timeout genérico de teste. |

## Acceptance Criteria
1. `bin/test:js` roda testes de componente e retorna exit code 0.
2. `bin/test:e2e` executa a jornada de smoke contra a aplicação real e retorna exit code 0.
3. Falha de E2E gera trace, screenshot e vídeo, e eles passam por redaction.
4. Existe lint que reprova seletor de teste baseado em classe CSS, provado por caso negativo.
5. Helpers cobrem os estados universais do doc 10 §25 e existe teste de exemplo para pelo menos loading, error e empty.
6. A checagem de acessibilidade roda na jornada de smoke e reprova violação de nível AA.
7. O relatório distingue retry de infraestrutura de retry de assertion.
8. Nenhum artefato de teste arquivado contém valor sensível.

## Required Tests
- **unit (frontend)**: componentes de exemplo nos estados loading/error/empty.
- **E2E**: jornada de smoke com verificação de acessibilidade.
- **security**: redaction de artefatos de falha.

## Quality Gates
Local Quality Gate classe React/TypeScript. E2E entra no Merge Gate a partir de `M00-11`.

## Definition of Done
Os 8 Acceptance Criteria satisfeitos, lint de seletor provado por caso negativo, redaction de artefatos verificada, Critical/High = 0.
