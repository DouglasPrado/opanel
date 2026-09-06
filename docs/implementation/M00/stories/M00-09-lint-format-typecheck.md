# M00-09 — Lint, format and typecheck toolchain

## Objective
Padronizar formatação, lint e checagem de tipos para Ruby e TypeScript, com execução incremental barata o suficiente para rodar em toda Story sem incentivar bypass.

## Outcome
`bin/lint` e `bin/format` operam sobre o repositório inteiro ou apenas sobre os arquivos alterados; `bin/typecheck` valida a árvore TypeScript; todos retornam exit code diferente de zero em violação.

## References
- `docs/annexes/I-engineering-playbook-quality-gates.md` §7 (padrões de código), §11 (Local Quality Gate), §12 (Pre-commit Gate)
- `docs/annexes/D-test-strategy.md` §4.1 (static checks)

## Preconditions
`M00-01` e `M00-04` done.

## Scope
- RuboCop com configuração do projeto, incluindo regras que refletem o Anexo I §7.1: proibição de `rescue` genérico que retorna sucesso, exigência de erro classificado.
- Linter e formatter de TypeScript/React com regra de import boundary: `app/frontend/` **não pode** importar código server-only.
- `tsc --noEmit` como typecheck.
- Modo incremental por arquivo alterado, usado pelo pre-commit.
- Regra de lint que reprova seletor de teste por classe CSS (contrato com `M00-08`).
- Documentação curta de como suprimir uma regra: exige comentário com justificativa e referência a Story/ADR; supressão sem justificativa é reprovada.

## Out of Scope
- Security scanners (`M00-10`).
- Fitness functions arquiteturais (`M00-13`).
- Métricas de complexidade cega como gate — o Anexo I §7.2 rejeita fragmentação artificial para satisfazer contador.

## Security Requirements
Uma regra de lint não pode ser desabilitada globalmente pelo agente para destravar Story (Anexo I §21.2). Supressões pontuais exigem justificativa referenciando Story ou ADR, e o CI reprova supressão sem justificativa.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Código formatado fora do padrão | `bin/format` corrige; `bin/lint` reprova se não corrigido. |
| Import de código server-only no React | Lint reprova com mensagem apontando a regra e o arquivo. |
| Supressão de regra sem justificativa | CI reprova. |
| Lint muito lento no pre-commit | Modo incremental limita ao diff; se ainda assim exceder o orçamento, a regra pesada migra para CI. |

## Acceptance Criteria
1. `bin/lint` executa RuboCop e o linter de TypeScript e retorna exit code 0 no estado limpo.
2. `bin/format` normaliza Ruby e TypeScript de forma idempotente.
3. `bin/typecheck` executa `tsc --noEmit` sem erro.
4. Modo incremental existe e opera apenas sobre arquivos alterados.
5. Regra de import boundary reprova, em caso negativo controlado, um import de código server-only dentro de `app/frontend/`.
6. Regra de `rescue` genérico que retorna sucesso reprova em caso negativo controlado.
7. Regra de seletor por classe CSS reprova em caso negativo controlado.
8. Supressão de regra sem justificativa é reprovada pelo CI, provado por caso negativo.
9. A documentação de supressão existe e é referenciada pela mensagem de erro do lint.

## Required Tests
- **unit/static**: um caso negativo por regra crítica (5, 6, 7, 8), provando que a regra detecta a violação.
- **integration**: `bin/lint`, `bin/format` e `bin/typecheck` no CI.

## Quality Gates
É a própria base do Local Quality Gate. A partir daqui, toda Story roda `bin/lint`, `bin/format` e `bin/typecheck` antes de declarar implementação pronta.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, cada regra crítica provada por caso negativo, execução incremental medida e dentro do orçamento de pre-commit, Critical/High = 0.
